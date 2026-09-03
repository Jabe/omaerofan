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
  return "Auto"
}

function modeStatus(mode) {
  return modeLabel(mode).toUpperCase()
}

function fanIcon(mode) {
  if (mode === "quiet") return "󰠝"
  if (mode === "gaming") return "󰈏"
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

if (typeof module !== "undefined") {
  module.exports = {
    num: num,
    clamp: clamp,
    clampFan: clampFan,
    clampBatt: clampBatt,
    parseStatus: parseStatus,
    modeLabel: modeLabel,
    modeStatus: modeStatus,
    fanIcon: fanIcon,
    hottestTemp: hottestTemp,
    tempTone: tempTone,
    powerCaption: powerCaption
  }
}
