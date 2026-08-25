#!/bin/bash
# Gigabyte EC firmware resets fan mode and charge limit on S3. Re-apply the
# last saved settings once the controller is writable again.

restore() {
  # Firmware often writes its own defaults for a beat after resume.
  sleep 1
  local i
  for i in $(seq 1 12); do
    if omaerofan restore >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done
}

dbus-monitor --system \
  "type='signal',sender='org.freedesktop.login1',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'" |
  while IFS= read -r line; do
    [[ $line == *"boolean false"* ]] || continue
    restore
  done
