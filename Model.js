function num(value, fallback) {
  var n = Number(value)
  return isFinite(n) ? n : (fallback || 0)
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value))
}

function clampFan(pct) {
  return clamp(Math.round(num(pct, 0)), 0, 100)
}

function clampBatt(pct) {
  return clamp(Math.round(num(pct, 60)), 20, 100)
}

function clampCurveMin(pct) {
  return clamp(Math.round(num(pct, 12)), 8, 40)
}

function clampCurveMax(pct) {
  return clamp(Math.round(num(pct, 40)), 25, 80)
}

function curveCaption(data, floorOverride, ceilOverride) {
  var floor = floorOverride === undefined || floorOverride < 0
    ? clampCurveMin(data && data.curve_min)
    : clampCurveMin(floorOverride)
  var ceil = ceilOverride === undefined || ceilOverride < 0
    ? clampCurveMax(data && data.curve_max)
    : clampCurveMax(ceilOverride)
  if (ceil < floor) ceil = floor
  var mapped = num(data && data.curve_pct, num(data && data.fan0_pct, 0))
  var pct = Math.max(floor, Math.min(ceil, mapped))
  var temp = hottestTemp(data)
  return pct + "% @ " + temp + "°  ·  " + floor + "–" + ceil + "%"
}

function curvePointsText(data, floorOverride, ceilOverride) {
  var floor = floorOverride === undefined || floorOverride < 0
    ? clampCurveMin(data && data.curve_min)
    : clampCurveMin(floorOverride)
  var ceil = ceilOverride === undefined || ceilOverride < 0
    ? clampCurveMax(data && data.curve_max)
    : clampCurveMax(ceilOverride)
  if (ceil < floor) ceil = floor
  var pts = (data && data.curve_points) || []
  var bits = []
  for (var i = 0; i < pts.length; i++) {
    if (!pts[i] || pts[i].length < 2) continue
    var duty = Math.max(floor, Math.min(ceil, num(pts[i][1], 0)))
    bits.push(pts[i][0] + "° " + duty + "%")
  }
  return bits.join("   ")
}

function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (!text) return { ok: false, installed: false, error: "empty status" }
  try {
    var data = JSON.parse(text)
    if (!data || typeof data !== "object")
      return { ok: false, installed: false, error: "invalid status" }
    return data
  } catch (e) {
    return { ok: false, installed: false, error: "invalid status" }
  }
}

function modeLabel(mode) {
  if (mode === "quiet") return "Quiet"
  if (mode === "gaming") return "Gaming"
  if (mode === "manual") return "Manual"
  if (mode === "curve") return "Curve"
  return "Auto"
}

function modeStatus(mode) {
  return modeLabel(mode).toUpperCase()
}

function fanIcon(mode) {
  if (mode === "quiet") return "󰠝"
  if (mode === "gaming") return "󰈏"
  if (mode === "curve") return "󰐰"
  if (mode === "manual") return "󰈐"
  return "󰈐"
}

function hottestTemp(data) {
  var cpu = num(data && data.cpu_temp, 0)
  var gpu = num(data && data.gpu_temp, 0)
  var mlb = num(data && data.mlb_temp, 0)
  return Math.max(cpu, gpu, mlb)
}

function tempTone(temp) {
  var t = num(temp, 0)
  if (t >= 85) return "hot"
  if (t >= 75) return "warm"
  return "ok"
}

function powerCaption(data) {
  var profile = String(data && data.power_profile || "")
  var pl1 = num(data && data.pl1_w, 0)
  var pl2 = num(data && data.pl2_w, 0)
  if (!profile && !pl1 && !pl2) return ""
  var name = profile || "rapl"
  if (!pl1 && !pl2) return name
  return name + " · " + pl1 + "/" + pl2 + " W"
}

var BRAKE_LABELS = {
  "prochot": "PROCHOT",
  "thermal": "thermal",
  "graphics": "graphics",
  "autonomous": "HWP",
  "vr-therm": "VR therm",
  "vr-tdc": "VR TDC",
  "edp": "EDP",
  "pl1": "RAPL PL1",
  "pl2": "RAPL PL2",
  "max-turbo": "max turbo",
  "turbo-atten": "turbo atten",
  "max-eff": "max efficiency"
}

function ghz(mhz) {
  var n = num(mhz, 0)
  if (n <= 0) return ""
  return (Math.round(n / 100) / 10).toFixed(1) + " GHz"
}

function isQuiet(data) {
  return !!(data && (data.quiet === 1 || data.quiet === true || data.mode === "quiet"))
}

function isCpuCapped(data) {
  return isQuiet(data)
}

function brakeParts(data) {
  var parts = []
  // Turbo-controller chatter and RAPL clipping are normal boost, not a cap.
  var skip = {
    "max-eff": true,
    "autonomous": true,
    "max-turbo": true,
    "turbo-atten": true,
    "pl1": true,
    "pl2": true,
    "graphics": true
  }
  var quiet = isQuiet(data)
  if (quiet) parts.push("EC quiet · EDP cap")
  var brakes = (data && data.brakes) || []
  for (var i = 0; i < brakes.length; i++) {
    var name = brakes[i]
    if (skip[name]) continue
    if (quiet && name === "edp") continue
    var label = BRAKE_LABELS[name] || name
    if (parts.indexOf(label) < 0) parts.push(label)
  }
  if (data && data.therm_prochot) {
    if (parts.indexOf("PROCHOT") < 0) parts.push("PROCHOT")
  }
  var hwp = num(data && data.hwp_max_mhz, 0)
  var turbo = num(data && data.turbo_mhz, 0)
  if (hwp > 0 && turbo > 0 && hwp + 50 < turbo)
    parts.push("HWP max " + ghz(hwp))
  var now = num(data && data.perf_mhz, 0)
  if (quiet && now > 0 && turbo > 0)
    parts.push(ghz(now) + " / " + ghz(turbo))
  return parts
}

function brakeCaption(data) {
  var parts = brakeParts(data)
  if (!parts.length) return "brake · none"
  return "brake · " + parts.join(" · ")
}

if (typeof module !== "undefined") {
  module.exports = {
    num: num,
    clamp: clamp,
    clampFan: clampFan,
    clampBatt: clampBatt,
    clampCurveMin: clampCurveMin,
    clampCurveMax: clampCurveMax,
    curveCaption: curveCaption,
    curvePointsText: curvePointsText,
    parseStatus: parseStatus,
    modeLabel: modeLabel,
    modeStatus: modeStatus,
    fanIcon: fanIcon,
    hottestTemp: hottestTemp,
    tempTone: tempTone,
    powerCaption: powerCaption,
    ghz: ghz,
    isQuiet: isQuiet,
    isCpuCapped: isCpuCapped,
    brakeParts: brakeParts,
    brakeCaption: brakeCaption
  }
}
