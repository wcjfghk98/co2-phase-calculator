const constants = {
  tripleK: 216.592,
  tripleC: -56.558,
  tripleBar: 5.185,
  criticalK: 304.1282,
  criticalC: 30.9782,
  criticalBar: 73.773,
  gasConstant: 8.314462618,
  sublimationHeat: 25230
};

const phases = {
  gas: "기체",
  liquid: "액체",
  solid: "고체",
  supercritical: "초임계",
  boundary: "상 경계"
};

const bounds = {
  minC: 0,
  maxC: 200,
  minBar: 0,
  maxBar: 200
};

const els = {
  temperature: document.querySelector("#temperature"),
  pressure: document.querySelector("#pressure"),
  targetPhase: document.querySelector("#targetPhase"),
  reset: document.querySelector("#reset"),
  chip: document.querySelector("#phaseChip"),
  title: document.querySelector("#resultTitle"),
  detail: document.querySelector("#resultDetail"),
  svg: document.querySelector("#phaseDiagram")
};

function cToK(celsius) {
  return celsius + 273.15;
}

function kToC(kelvin) {
  return kelvin - 273.15;
}

function vaporPressureBar(kelvin) {
  if (kelvin < constants.tripleK || kelvin > constants.criticalK) return NaN;
  const theta = 1 - kelvin / constants.criticalK;
  const a = [-7.0602087, 1.9391218, -1.6463597, -3.2995634];
  const lnRatio = (constants.criticalK / kelvin) *
    (a[0] * theta + a[1] * theta ** 1.5 + a[2] * theta ** 2 + a[3] * theta ** 4);
  return constants.criticalBar * Math.exp(lnRatio);
}

function sublimationPressureBar(kelvin) {
  if (kelvin > constants.tripleK) return NaN;
  return constants.tripleBar *
    Math.exp((-constants.sublimationHeat / constants.gasConstant) * (1 / kelvin - 1 / constants.tripleK));
}

function meltingPressureBar(kelvin) {
  if (kelvin < constants.tripleK) return NaN;
  const aBar = 4030;
  const b = 2.58;
  return constants.tripleBar + aBar * ((kelvin / constants.tripleK) ** b - 1);
}

function nearlyEqual(a, b, tolerance = 0.01) {
  return Math.abs(a - b) <= Math.max(tolerance, Math.abs(b) * 0.002);
}

function classify(celsius, bar) {
  const kelvin = cToK(celsius);
  if (!Number.isFinite(kelvin) || !Number.isFinite(bar) || bar <= 0 || kelvin <= 0) {
    return { phase: null, note: "온도는 절대영도보다 높고 압력은 0보다 커야 합니다." };
  }

  if (nearlyEqual(kelvin, constants.tripleK, 0.08) && nearlyEqual(bar, constants.tripleBar, 0.04)) {
    return { phase: "boundary", note: "삼중점 근처입니다. 고체, 액체, 기체가 공존할 수 있습니다." };
  }

  if (kelvin < constants.tripleK) {
    const pSub = sublimationPressureBar(kelvin);
    if (nearlyEqual(bar, pSub)) {
      return { phase: "boundary", note: "승화선 근처입니다. 고체와 기체가 공존할 수 있습니다." };
    }
    return bar > pSub
      ? { phase: "solid", note: `승화압 ${fmtBar(pSub)}보다 높아 고체 영역입니다.` }
      : { phase: "gas", note: `승화압 ${fmtBar(pSub)}보다 낮아 기체 영역입니다.` };
  }

  const pMelt = meltingPressureBar(kelvin);
  if (bar >= pMelt || nearlyEqual(bar, pMelt, 0.2)) {
    return nearlyEqual(bar, pMelt, 0.2)
      ? { phase: "boundary", note: "용융선 근처입니다. 고체와 유체상이 공존할 수 있습니다." }
      : { phase: "solid", note: `용융압 ${fmtBar(pMelt)}보다 높아 고체 영역입니다.` };
  }

  if (kelvin > constants.criticalK) {
    if (bar > constants.criticalBar) {
      return { phase: "supercritical", note: "임계온도와 임계압력을 모두 초과합니다." };
    }
    return { phase: "gas", note: "임계온도보다 높지만 임계압력보다 낮아 기체 영역입니다." };
  }

  const pSat = vaporPressureBar(kelvin);
  if (nearlyEqual(bar, pSat, 0.05)) {
    return { phase: "boundary", note: "액체-기체 포화선 근처입니다. 두 상이 공존할 수 있습니다." };
  }
  return bar > pSat
    ? { phase: "liquid", note: `포화압 ${fmtBar(pSat)}보다 높고 용융압보다 낮아 액체 영역입니다.` }
    : { phase: "gas", note: `포화압 ${fmtBar(pSat)}보다 낮아 기체 영역입니다.` };
}

function invertMonotonic(target, lowK, highK, fn) {
  let low = lowK;
  let high = highK;
  for (let i = 0; i < 80; i += 1) {
    const mid = (low + high) / 2;
    if (fn(mid) < target) low = mid;
    else high = mid;
  }
  return (low + high) / 2;
}

function rangeForTemperature(celsius, phase) {
  const kelvin = cToK(celsius);
  if (!Number.isFinite(kelvin) || kelvin <= 0) return invalid("온도는 절대영도보다 높아야 합니다.");
  const pMelt = kelvin >= constants.tripleK ? meltingPressureBar(kelvin) : null;

  if (phase === "solid") {
    const boundary = kelvin < constants.tripleK ? sublimationPressureBar(kelvin) : pMelt;
    return ok(`${fmtBar(boundary)} 이상`, `이 온도에서는 압력이 ${fmtBar(boundary)} 이상이면 고체 영역입니다.`);
  }

  if (phase === "gas") {
    if (kelvin < constants.tripleK) {
      const pSub = sublimationPressureBar(kelvin);
      return ok(`0 ~ ${fmtBar(pSub)} 미만`, "이 온도에서는 승화압보다 낮은 압력에서 기체입니다.");
    }
    if (kelvin < constants.criticalK) {
      const pSat = vaporPressureBar(kelvin);
      return ok(`0 ~ ${fmtBar(pSat)} 미만`, "이 온도에서는 포화압보다 낮은 압력에서 기체입니다.");
    }
    return ok(`0 ~ ${fmtBar(constants.criticalBar)} 미만`, "임계온도보다 높으므로 임계압력 미만에서는 기체로 봅니다.");
  }

  if (phase === "liquid") {
    if (kelvin <= constants.tripleK || kelvin >= constants.criticalK) {
      return none("이 온도에서는 안정한 액체 영역이 없습니다.");
    }
    const pSat = vaporPressureBar(kelvin);
    return ok(`${fmtBar(pSat)} 초과 ~ ${fmtBar(pMelt)} 미만`, "포화압보다 높고 용융압보다 낮은 범위가 액체 영역입니다.");
  }

  if (phase === "supercritical") {
    if (kelvin <= constants.criticalK) return none("초임계는 임계온도 31.0°C를 초과해야 합니다.");
    return ok(`${fmtBar(constants.criticalBar)} 초과 ~ ${fmtBar(pMelt)} 미만`, "임계압력보다 높고, 초고압 고체화 경계보다 낮은 범위입니다.");
  }

  return invalid("알 수 없는 상입니다.");
}

function rangeForPressure(bar, phase) {
  if (!Number.isFinite(bar) || bar <= 0) return invalid("압력은 0보다 커야 합니다.");
  const hasSublimationRoot = bar <= constants.tripleBar;
  const meltTemp = bar >= constants.tripleBar
    ? invertMonotonic(bar, constants.tripleK, cToK(bounds.maxC), meltingPressureBar)
    : null;

  if (phase === "solid") {
    if (hasSublimationRoot) {
      const tSub = invertMonotonic(bar, cToK(bounds.minC), constants.tripleK, sublimationPressureBar);
      return ok(`${fmtC(kToC(tSub))} 이하`, "이 압력에서는 승화선보다 낮은 온도에서 고체입니다.");
    }
    return ok(`${fmtC(kToC(meltTemp))} 미만`, "이 압력에서는 용융선보다 낮은 온도에서 고체입니다.");
  }

  if (phase === "gas") {
    if (bar < constants.tripleBar) {
      const tSub = invertMonotonic(bar, cToK(bounds.minC), constants.tripleK, sublimationPressureBar);
      return ok(`${fmtC(kToC(tSub))} 초과`, "이 압력에서는 승화온도보다 높으면 기체입니다.");
    }
    if (bar < constants.criticalBar) {
      const tSat = invertMonotonic(bar, constants.tripleK, constants.criticalK, vaporPressureBar);
      return ok(`${fmtC(kToC(tSat))} 초과`, "이 압력에서는 끓는점보다 높은 온도에서 기체입니다.");
    }
    return none("임계압력 이상에서는 안정한 기체 영역이 없습니다. 임계온도 이상은 초임계입니다.");
  }

  if (phase === "liquid") {
    if (bar <= constants.tripleBar) return none("삼중점 압력 이하에서는 안정한 액체 영역이 없습니다.");
    if (bar < constants.criticalBar) {
      const tSat = invertMonotonic(bar, constants.tripleK, constants.criticalK, vaporPressureBar);
      return ok(`${fmtC(kToC(meltTemp))} 초과 ~ ${fmtC(kToC(tSat))} 미만`, "용융온도와 포화온도 사이가 액체 영역입니다.");
    }
    return ok(`${fmtC(kToC(meltTemp))} 초과 ~ ${fmtC(constants.criticalC)} 미만`, "임계압력 이상에서는 임계온도 아래의 압축 액체 영역입니다.");
  }

  if (phase === "supercritical") {
    if (bar <= constants.criticalBar) return none("초임계는 임계압력 73.8 bar를 초과해야 합니다.");
    return ok(`${fmtC(constants.criticalC)} 초과 ~ ${fmtC(kToC(meltTemp))} 미만`, "임계온도보다 높고 용융선보다 낮은 범위입니다.");
  }

  return invalid("알 수 없는 상입니다.");
}

function ok(range, detail) {
  return { status: "ok", range, detail };
}

function none(detail) {
  return { status: "none", detail };
}

function invalid(detail) {
  return { status: "invalid", detail };
}

function fmtBar(value) {
  if (!Number.isFinite(value)) return "-";
  if (value >= 1000) return `${Math.round(value).toLocaleString("ko-KR")} bar`;
  if (value >= 10) return `${value.toFixed(1)} bar`;
  if (value >= 1) return `${value.toFixed(2)} bar`;
  return `${value.toPrecision(2)} bar`;
}

function fmtC(value) {
  return `${value.toFixed(1)}°C`;
}

function readNumber(input) {
  if (input.value.trim() === "") return null;
  const value = Number(input.value);
  return Number.isFinite(value) ? value : NaN;
}

function updateResult(chipText, chipClass, title, detail) {
  els.chip.className = `phase-chip${chipClass ? ` ${chipClass}` : ""}`;
  els.chip.textContent = chipText;
  els.title.textContent = title;
  els.detail.textContent = detail;
}

function showTargetPrompt() {
  updateResult("상을 선택하세요", "", "원하는 상을 선택하면 가능한 조건 범위를 보여줍니다.",
    "온도나 압력 중 하나만 입력한 경우에는 원하는 상을 먼저 선택해 주세요.");
}

function calculate() {
  const temperature = readNumber(els.temperature);
  const pressure = readNumber(els.pressure);
  const target = els.targetPhase.value;

  if (temperature !== null && pressure !== null) {
    const state = classify(temperature, pressure);
    if (!state.phase) {
      updateResult("입력 확인", "", "계산할 수 없는 조건입니다.", state.note);
      drawDiagram(null);
      return;
    }
    updateResult(phases[state.phase], state.phase === "boundary" ? "" : state.phase,
      `${fmtC(temperature)}, ${fmtBar(pressure)}에서는 ${phases[state.phase]}입니다.`,
      state.note);
    drawDiagram({ celsius: temperature, bar: pressure });
    return;
  }

  if ((temperature !== null || pressure !== null) && !target) {
    showTargetPrompt();
    drawDiagram(null);
    return;
  }

  if (temperature !== null) {
    const range = rangeForTemperature(temperature, target);
    const title = range.status === "ok"
      ? `${fmtC(temperature)}에서 ${phases[target]} 압력 범위: ${range.range}`
      : `${fmtC(temperature)}에서 ${phases[target]} 조건이 없습니다.`;
    updateResult(phases[target], target, title, range.detail);
    drawDiagram(null);
    return;
  }

  if (pressure !== null) {
    const range = rangeForPressure(pressure, target);
    const title = range.status === "ok"
      ? `${fmtBar(pressure)}에서 ${phases[target]} 온도 범위: ${range.range}`
      : `${fmtBar(pressure)}에서 ${phases[target]} 조건이 없습니다.`;
    updateResult(phases[target], target, title, range.detail);
    drawDiagram(null);
    return;
  }

  updateResult("조건을 입력하세요", "", "온도와 압력을 입력하거나, 한 조건과 원하는 상을 선택해 주세요.",
    "두 값을 모두 넣으면 현재 상을 판정하고 상평형도에 포인트를 표시합니다.");
  drawDiagram(null);
}

function reset() {
  els.temperature.value = "";
  els.pressure.value = "";
  els.targetPhase.value = "";
  calculate();
}

function project(celsius, bar) {
  const margin = { left: 88, right: 28, top: 24, bottom: 58 };
  const width = 720 - margin.left - margin.right;
  const height = 520 - margin.top - margin.bottom;
  const x = margin.left + ((celsius - bounds.minC) / (bounds.maxC - bounds.minC)) * width;
  const y = margin.top + (1 - ((bar - bounds.minBar) / (bounds.maxBar - bounds.minBar))) * height;
  return { x, y };
}

function pathFrom(points) {
  return points
    .filter((point) => Number.isFinite(point.bar) && point.bar >= bounds.minBar && point.bar <= bounds.maxBar)
    .map((point, index) => {
      const p = project(point.celsius, point.bar);
      return `${index === 0 ? "M" : "L"} ${p.x.toFixed(1)} ${p.y.toFixed(1)}`;
    })
    .join(" ");
}

function curvePoints(startC, endC, count, fn) {
  return Array.from({ length: count }, (_, index) => {
    const celsius = startC + ((endC - startC) * index) / (count - 1);
    return { celsius, bar: fn(cToK(celsius)) };
  });
}

function svgEl(name, attrs = {}, text = "") {
  const el = document.createElementNS("http://www.w3.org/2000/svg", name);
  Object.entries(attrs).forEach(([key, value]) => el.setAttribute(key, value));
  if (text) el.textContent = text;
  return el;
}

function addSupercriticalRegion() {
  const points = [
    { celsius: constants.criticalC, bar: constants.criticalBar },
    { celsius: bounds.maxC, bar: constants.criticalBar },
    { celsius: bounds.maxC, bar: bounds.maxBar },
    { celsius: constants.criticalC, bar: bounds.maxBar }
  ];
  const d = `${pathFrom(points)} Z`;
  els.svg.append(svgEl("path", { d, class: "super-region" }));
}

function drawDiagram(marker) {
  els.svg.replaceChildren();
  addSupercriticalRegion();

  const pressureTicks = [0, 50, 100, 150, 200];
  const tempTicks = [0, 50, 100, 150, 200];
  pressureTicks.forEach((bar) => {
    const a = project(bounds.minC, bar);
    const b = project(bounds.maxC, bar);
    els.svg.append(svgEl("line", { x1: a.x, y1: a.y, x2: b.x, y2: b.y, class: "grid" }));
    els.svg.append(svgEl("text", { x: 28, y: a.y + 5, class: "tick" }, `${bar}`));
  });
  tempTicks.forEach((celsius) => {
    const a = project(celsius, bounds.minBar);
    const b = project(celsius, bounds.maxBar);
    els.svg.append(svgEl("line", { x1: a.x, y1: a.y, x2: b.x, y2: b.y, class: "grid" }));
    els.svg.append(svgEl("text", { x: a.x - 17, y: 492, class: "tick" }, `${celsius}`));
  });

  const origin = project(bounds.minC, bounds.minBar);
  const topLeft = project(bounds.minC, bounds.maxBar);
  const bottomRight = project(bounds.maxC, bounds.minBar);
  els.svg.append(svgEl("line", { x1: topLeft.x, y1: topLeft.y, x2: origin.x, y2: origin.y, class: "axis" }));
  els.svg.append(svgEl("line", { x1: origin.x, y1: origin.y, x2: bottomRight.x, y2: bottomRight.y, class: "axis" }));
  const axisCenterX = (origin.x + bottomRight.x) / 2;
  const axisCenterY = (topLeft.y + origin.y) / 2;
  els.svg.append(svgEl("text", { x: axisCenterX, y: 514, class: "axis-title centered" }, "온도 (°C)"));
  els.svg.append(svgEl("text", {
    x: -axisCenterY,
    y: 20,
    class: "axis-title",
    transform: "rotate(-90)"
  }, "압력 (bar)"));

  const gasLabel = project(115, 38);
  const liquidLabel = project(14, 142);
  const superLabel = project(118, 142);
  els.svg.append(svgEl("text", { x: gasLabel.x - 24, y: gasLabel.y, class: "region" }, "기체"));
  els.svg.append(svgEl("text", { x: liquidLabel.x - 24, y: liquidLabel.y, class: "region" }, "액체"));
  els.svg.append(svgEl("text", { x: superLabel.x - 40, y: superLabel.y, class: "region" }, "초임계"));

  const vapor = curvePoints(bounds.minC, constants.criticalC, 120, vaporPressureBar);
  els.svg.append(svgEl("path", { d: pathFrom(vapor), class: "boundary vapor" }));

  const triple = project(constants.tripleC, constants.tripleBar);
  const critical = project(constants.criticalC, constants.criticalBar);
  if (constants.tripleC >= bounds.minC) {
    els.svg.append(svgEl("circle", { cx: triple.x, cy: triple.y, r: 5, fill: "#263238" }));
    els.svg.append(svgEl("text", { x: triple.x + 8, y: triple.y + 20, class: "label" }, "삼중점"));
  }
  els.svg.append(svgEl("circle", { cx: critical.x, cy: critical.y, r: 5, fill: "#263238" }));
  els.svg.append(svgEl("text", { x: critical.x + 8, y: critical.y - 10, class: "label" }, "임계점"));

  if (marker && marker.bar >= bounds.minBar && marker.bar <= bounds.maxBar &&
      marker.celsius >= bounds.minC && marker.celsius <= bounds.maxC) {
    const m = project(marker.celsius, marker.bar);
    els.svg.append(svgEl("circle", { cx: m.x, cy: m.y, r: 18, class: "marker-ring" }));
    els.svg.append(svgEl("circle", { cx: m.x, cy: m.y, r: 7, class: "marker" }));
  }
}

els.reset.addEventListener("click", reset);
els.temperature.addEventListener("input", calculate);
els.pressure.addEventListener("input", calculate);
els.targetPhase.addEventListener("change", calculate);

calculate();
