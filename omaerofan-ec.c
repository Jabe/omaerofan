#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/io.h>
#include <sys/stat.h>
#include <unistd.h>

#define EC_DATA 0x62
#define EC_SC 0x66
#define EC_OBF 0x01
#define EC_IBF 0x02
#define EC_CMD_READ 0x80
#define EC_CMD_WRITE 0x81

#define REG_ENABLE 0x01
#define REG_FIXED 0x06
#define REG_QUIET 0x08
#define REG_GAMING 0x0C
#define REG_CUSTOM 0x0D
#define REG_CHARGE 0x0F
#define REG_FANCTL 0x13
#define REG_CPU_TEMP 0x60
#define REG_GPU_TEMP 0x61
#define REG_MLB_TEMP 0x62
#define REG_CHARGE_PCT 0xA9
#define REG_FAN0 0xB0
#define REG_FAN1 0xB1
#define REG_FAN0_RPM 0xFC
#define REG_FAN1_RPM 0xFE

#define BIT_FIXED 4
#define BIT_QUIET 6
#define BIT_GAMING 4
#define BIT_CUSTOM 0
#define BIT_DEEP 7
#define BIT_CHARGE 2
#define BIT_FANCTL 3

#define DUTY_MAX 229

static const char *EC_SYS_PATH = "/sys/kernel/debug/ec/ec0/io";
static const char *EC_DEV_PATH = "/dev/ec";

enum backend { BACKEND_NONE, BACKEND_SYSFS, BACKEND_DEV, BACKEND_PORT };

static enum backend backend = BACKEND_NONE;
static int ec_fd = -1;

static void die(const char *msg) {
  fprintf(stderr, "omaerofan-ec: %s\n", msg);
  exit(1);
}

static void die_errno(const char *msg) {
  fprintf(stderr, "omaerofan-ec: %s: %s\n", msg, strerror(errno));
  exit(1);
}

static int allowed_reg(uint8_t reg) {
  switch (reg) {
  case REG_ENABLE:
  case REG_FIXED:
  case REG_QUIET:
  case REG_GAMING:
  case REG_CUSTOM:
  case REG_CHARGE:
  case REG_FANCTL:
  case REG_CHARGE_PCT:
  case REG_FAN0:
  case REG_FAN1:
    return 1;
  default:
    return 0;
  }
}

static int wait_mask(int set, uint8_t mask, int usec) {
  for (int i = 0; i < usec / 50; i++) {
    uint8_t st = inb(EC_SC);
    if (set) {
      if (st & mask)
        return 0;
    } else if (!(st & mask)) {
      return 0;
    }
    usleep(50);
  }
  return -1;
}

static int port_read(uint8_t addr, uint8_t *val) {
  if (wait_mask(0, EC_IBF, 20000) < 0)
    return -1;
  outb(EC_CMD_READ, EC_SC);
  if (wait_mask(0, EC_IBF, 20000) < 0)
    return -1;
  outb(addr, EC_DATA);
  if (wait_mask(1, EC_OBF, 20000) < 0)
    return -1;
  *val = inb(EC_DATA);
  return 0;
}

static int port_write(uint8_t addr, uint8_t val) {
  if (wait_mask(0, EC_IBF, 20000) < 0)
    return -1;
  outb(EC_CMD_WRITE, EC_SC);
  if (wait_mask(0, EC_IBF, 20000) < 0)
    return -1;
  outb(addr, EC_DATA);
  if (wait_mask(0, EC_IBF, 20000) < 0)
    return -1;
  outb(val, EC_DATA);
  return 0;
}

static int load_ec_sys(void) {
  if (access(EC_SYS_PATH, F_OK) == 0)
    return 0;
  if (system("modprobe ec_sys write_support=1 >/dev/null 2>&1") != 0)
    return -1;
  for (int i = 0; i < 20; i++) {
    if (access(EC_SYS_PATH, F_OK) == 0)
      return 0;
    usleep(50000);
  }
  return -1;
}

static int open_backend(void) {
  if (load_ec_sys() == 0) {
    ec_fd = open(EC_SYS_PATH, O_RDWR);
    if (ec_fd >= 0) {
      backend = BACKEND_SYSFS;
      return 0;
    }
    ec_fd = open(EC_SYS_PATH, O_RDONLY);
    if (ec_fd >= 0) {
      backend = BACKEND_SYSFS;
      return 0;
    }
  }

  ec_fd = open(EC_DEV_PATH, O_RDWR);
  if (ec_fd >= 0) {
    backend = BACKEND_DEV;
    return 0;
  }

  if (ioperm(EC_DATA, 1, 1) == 0 && ioperm(EC_SC, 1, 1) == 0) {
    backend = BACKEND_PORT;
    return 0;
  }

  return -1;
}

static const char *backend_name(void) {
  switch (backend) {
  case BACKEND_SYSFS:
    return "ec_sys";
  case BACKEND_DEV:
    return "/dev/ec";
  case BACKEND_PORT:
    return "port";
  default:
    return "none";
  }
}

static int ec_read(uint8_t addr, uint8_t *val) {
  if (backend == BACKEND_PORT)
    return port_read(addr, val);
  if (pread(ec_fd, val, 1, addr) != 1)
    return -1;
  return 0;
}

static int ec_write(uint8_t addr, uint8_t val) {
  if (backend == BACKEND_PORT)
    return port_write(addr, val);
  if (pwrite(ec_fd, &val, 1, addr) != 1)
    return -1;
  return 0;
}

static uint8_t must_read(uint8_t addr) {
  uint8_t val = 0;
  if (ec_read(addr, &val) < 0)
    die_errno("EC read failed");
  return val;
}

static void must_write(uint8_t addr, uint8_t val) {
  if (ec_write(addr, val) < 0)
    die_errno("EC write failed");
}

static int bit_get(uint8_t addr, int bit) { return (must_read(addr) >> bit) & 1; }

static void bit_set(uint8_t addr, int bit, int on) {
  uint8_t val = must_read(addr);
  if (on)
    val |= (uint8_t)(1u << bit);
  else
    val &= (uint8_t)~(1u << bit);
  must_write(addr, val);
}

static int duty_to_pct(int duty) {
  if (duty <= 0)
    return 0;
  if (duty >= DUTY_MAX)
    return 100;
  return (duty * 100 + DUTY_MAX / 2) / DUTY_MAX;
}

static int pct_to_duty(int pct) {
  if (pct <= 0)
    return 0;
  if (pct > 100)
    pct = 100;
  return (pct * DUTY_MAX + 50) / 100;
}

static uint16_t read16be(uint8_t addr) {
  return ((uint16_t)must_read(addr) << 8) | must_read((uint8_t)(addr + 1));
}

static const char *detect_mode(void) {
  if (bit_get(REG_QUIET, BIT_QUIET))
    return "quiet";
  if (bit_get(REG_GAMING, BIT_GAMING))
    return "gaming";
  if (bit_get(REG_CUSTOM, BIT_CUSTOM) || bit_get(REG_FIXED, BIT_FIXED))
    return "manual";
  return "auto";
}

static void enable_control(void) {
  bit_set(REG_FANCTL, BIT_FANCTL, 1);
}

static void apply_mode(const char *mode) {
  enable_control();
  if (strcmp(mode, "auto") == 0) {
    bit_set(REG_QUIET, BIT_QUIET, 0);
    bit_set(REG_CUSTOM, BIT_CUSTOM, 0);
    bit_set(REG_FIXED, BIT_FIXED, 0);
    bit_set(REG_GAMING, BIT_GAMING, 0);
    bit_set(REG_CUSTOM, BIT_DEEP, 0);
  } else if (strcmp(mode, "quiet") == 0) {
    bit_set(REG_QUIET, BIT_QUIET, 1);
    bit_set(REG_CUSTOM, BIT_CUSTOM, 0);
    bit_set(REG_FIXED, BIT_FIXED, 0);
    bit_set(REG_GAMING, BIT_GAMING, 0);
    bit_set(REG_CUSTOM, BIT_DEEP, 0);
  } else if (strcmp(mode, "gaming") == 0) {
    bit_set(REG_QUIET, BIT_QUIET, 0);
    bit_set(REG_CUSTOM, BIT_CUSTOM, 0);
    bit_set(REG_FIXED, BIT_FIXED, 0);
    bit_set(REG_GAMING, BIT_GAMING, 1);
    bit_set(REG_CUSTOM, BIT_DEEP, 0);
  } else if (strcmp(mode, "manual") == 0) {
    bit_set(REG_QUIET, BIT_QUIET, 0);
    bit_set(REG_CUSTOM, BIT_CUSTOM, 1);
    bit_set(REG_FIXED, BIT_FIXED, 1);
    bit_set(REG_GAMING, BIT_GAMING, 0);
    bit_set(REG_CUSTOM, BIT_DEEP, 0);
  } else {
    die("mode must be auto, quiet, gaming, or manual");
  }
}

static void apply_fans(int cpu_pct, int gpu_pct) {
  if (cpu_pct < 0 || cpu_pct > 100 || gpu_pct < 0 || gpu_pct > 100)
    die("fan percent must be 0-100");
  apply_mode("manual");
  must_write(REG_FAN0, (uint8_t)pct_to_duty(cpu_pct));
  must_write(REG_FAN1, (uint8_t)pct_to_duty(gpu_pct));
}

static void apply_battery(int on, int pct) {
  if (on) {
    if (pct < 20 || pct > 100)
      die("battery limit must be 20-100");
    uint8_t reg = must_read(REG_CHARGE);
    must_write(REG_CHARGE, (uint8_t)((reg & (uint8_t)~0x04) | 0x04));
    must_write(REG_CHARGE_PCT, (uint8_t)pct);
  } else {
    uint8_t reg = must_read(REG_CHARGE);
    must_write(REG_CHARGE, (uint8_t)(reg & (uint8_t)~0x04));
  }
}

static void print_status(void) {
  uint8_t fan0 = must_read(REG_FAN0);
  uint8_t fan1 = must_read(REG_FAN1);
  uint8_t charge = must_read(REG_CHARGE);
  int batt_on = (charge >> BIT_CHARGE) & 1;
  printf("{\n");
  printf("  \"backend\": \"%s\",\n", backend_name());
  printf("  \"cpu_temp\": %u,\n", must_read(REG_CPU_TEMP));
  printf("  \"gpu_temp\": %u,\n", must_read(REG_GPU_TEMP));
  printf("  \"mlb_temp\": %u,\n", must_read(REG_MLB_TEMP));
  printf("  \"fan0_rpm\": %u,\n", read16be(REG_FAN0_RPM));
  printf("  \"fan1_rpm\": %u,\n", read16be(REG_FAN1_RPM));
  printf("  \"fan_control\": %d,\n", bit_get(REG_FANCTL, BIT_FANCTL));
  printf("  \"quiet\": %d,\n", bit_get(REG_QUIET, BIT_QUIET));
  printf("  \"gaming\": %d,\n", bit_get(REG_GAMING, BIT_GAMING));
  printf("  \"custom\": %d,\n", bit_get(REG_CUSTOM, BIT_CUSTOM));
  printf("  \"fixed\": %d,\n", bit_get(REG_FIXED, BIT_FIXED));
  printf("  \"deep\": %d,\n", bit_get(REG_CUSTOM, BIT_DEEP));
  printf("  \"fan0_duty\": %u,\n", fan0);
  printf("  \"fan1_duty\": %u,\n", fan1);
  printf("  \"fan0_pct\": %d,\n", duty_to_pct(fan0));
  printf("  \"fan1_pct\": %d,\n", duty_to_pct(fan1));
  printf("  \"mode\": \"%s\",\n", detect_mode());
  printf("  \"battery_on\": %d,\n", batt_on);
  printf("  \"battery_limit\": %u\n", must_read(REG_CHARGE_PCT));
  printf("}\n");
}

static void print_dump(void) {
  uint8_t buf[256];
  for (int i = 0; i < 256; i++)
    buf[i] = must_read((uint8_t)i);
  printf("backend %s\n", backend_name());
  for (int row = 0; row < 16; row++) {
    printf("%02X:", row * 16);
    for (int col = 0; col < 16; col++)
      printf(" %02X", buf[row * 16 + col]);
    printf("\n");
  }
}

static void usage(void) {
  fprintf(stderr,
          "usage: omaerofan-ec status\n"
          "       omaerofan-ec dump\n"
          "       omaerofan-ec mode auto|quiet|gaming|manual\n"
          "       omaerofan-ec fans <cpu-pct> <gpu-pct>\n"
          "       omaerofan-ec battery off\n"
          "       omaerofan-ec battery <pct>\n"
          "       omaerofan-ec write <reg> <val>\n");
  exit(2);
}

static unsigned parse_num(const char *s) {
  char *end = NULL;
  unsigned long v = strtoul(s, &end, 0);
  if (!s[0] || !end || *end || v > 255)
    die("number must be 0-255");
  return (unsigned)v;
}

int main(int argc, char **argv) {
  if (geteuid() != 0)
    die("must run as root");
  if (argc < 2)
    usage();
  if (open_backend() < 0)
    die("no EC access (ec_sys, /dev/ec, or ports)");

  if (strcmp(argv[1], "status") == 0) {
    print_status();
  } else if (strcmp(argv[1], "dump") == 0) {
    print_dump();
  } else if (strcmp(argv[1], "mode") == 0 && argc == 3) {
    apply_mode(argv[2]);
    print_status();
  } else if (strcmp(argv[1], "fans") == 0 && argc == 4) {
    apply_fans(atoi(argv[2]), atoi(argv[3]));
    print_status();
  } else if (strcmp(argv[1], "battery") == 0 && argc == 3) {
    if (strcmp(argv[2], "off") == 0)
      apply_battery(0, 0);
    else
      apply_battery(1, atoi(argv[2]));
    print_status();
  } else if (strcmp(argv[1], "write") == 0 && argc == 4) {
    uint8_t reg = (uint8_t)parse_num(argv[2]);
    uint8_t val = (uint8_t)parse_num(argv[3]);
    if (!allowed_reg(reg))
      die("refusing write to unknown register");
    must_write(reg, val);
    print_status();
  } else {
    usage();
  }

  if (ec_fd >= 0)
    close(ec_fd);
  return 0;
}
