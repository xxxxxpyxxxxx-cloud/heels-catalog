(() => {
  const data = Array.isArray(window.SHOE_DATA) ? window.SHOE_DATA : [];

  const facetGroups = [
    { key: "style", label: "款式" },
    { key: "toe", label: "鞋頭" },
    { key: "heelStyle", label: "鞋跟" },
    { key: "material", label: "材質" },
    { key: "color", label: "顏色" },
  ];

  const state = {
    query: "",
    minH: 0,
    maxH: 30,
    view: "grid", // grid | list
    selected: Object.fromEntries(facetGroups.map((g) => [g.key, new Set()])),
  };

  const heightBounds = computeHeightBounds();

  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));
  const cssEscape = (s) => {
    if (window.CSS && typeof window.CSS.escape === "function") return window.CSS.escape(`${s}`);
    return `${s}`.replace(/[^a-zA-Z0-9_-]/g, "\\$&");
  };

  const els = {
    count: $("#count"),
    q: $("#q"),
    openFilters: $("#openFilters"),
    clear: $("#clear"),
    toggleView: $("#toggleView"),
    chipBar: $("#chipBar"),
    grid: $("#grid"),
    empty: $("#empty"),
    drawer: $("#drawer"),
    drawerOverlay: $("#drawerOverlay"),
    closeDrawer: $("#closeDrawer"),
    rangeMin: $("#rangeMin"),
    rangeMax: $("#rangeMax"),
    rangeMinVal: $("#rangeMinVal"),
    rangeMaxVal: $("#rangeMaxVal"),
    facetMount: $("#facetMount"),
    modal: $("#modal"),
    modalOverlay: $("#modalOverlay"),
    modalClose: $("#modalClose"),
    modalImg: $("#modalImg"),
    modalTitle: $("#modalTitle"),
    modalMeta: $("#modalMeta"),
    modalCopyName: $("#modalCopyName"),
    modalCopyRow: $("#modalCopyRow"),
    modalAddFilters: $("#modalAddFilters"),
  };

  function uniqValues(key) {
    const set = new Set();
    for (const item of data) {
      const v = (item?.[key] ?? "").toString().trim();
      if (v) set.add(v);
    }
    return Array.from(set).sort((a, b) => a.localeCompare(b, "zh-Hant"));
  }

  function clamp(n, a, b) {
    return Math.max(a, Math.min(b, n));
  }

  function escapeHtml(s) {
    return (s ?? "")
      .toString()
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;");
  }

  function normalizeHay(item) {
    return [
      item?.filename,
      item?.style,
      item?.toe,
      item?.heelStyle,
      item?.material,
      item?.color,
      item?.heelHeightCm,
    ]
      .filter((x) => x !== null && x !== undefined && `${x}`.trim() !== "")
      .join(" / ")
      .toLowerCase();
  }

  function isHeightInRange(item, minH, maxH) {
    const h = Number(item?.heelHeightCm);
    if (!Number.isFinite(h)) return true;
    return h >= minH && h <= maxH;
  }

  function matchesFacet(item, key, set) {
    if (!set || set.size === 0) return true;
    return set.has((item?.[key] ?? "").toString().trim());
  }

  function applyFilters(items, st) {
    const q = (st.query ?? "").trim().toLowerCase();
    let minH = Number(st.minH);
    let maxH = Number(st.maxH);
    if (minH > maxH) [minH, maxH] = [maxH, minH];

    return items.filter((item) => {
      if (!isHeightInRange(item, minH, maxH)) return false;
      if (q) {
        const hay = normalizeHay(item);
        if (!hay.includes(q)) return false;
      }
      for (const g of facetGroups) {
        if (!matchesFacet(item, g.key, st.selected[g.key])) return false;
      }
      return true;
    });
  }

  function computeHeightBounds() {
    const heights = data.map((x) => Number(x?.heelHeightCm)).filter((x) => Number.isFinite(x));
    if (!heights.length) return { min: 0, max: 30 };
    const min = Math.max(0, Math.floor(Math.min(...heights)));
    const max = Math.min(30, Math.ceil(Math.max(...heights)));
    return { min, max };
  }

  function setDrawerOpen(open) {
    els.drawer.dataset.open = open ? "1" : "0";
    els.drawerOverlay.dataset.open = open ? "1" : "0";
    document.body.dataset.drawerOpen = open ? "1" : "0";
  }

  function setModalOpen(open) {
    els.modal.dataset.open = open ? "1" : "0";
    els.modalOverlay.dataset.open = open ? "1" : "0";
    document.body.dataset.modalOpen = open ? "1" : "0";
  }

  function copyText(text) {
    const s = `${text ?? ""}`;
    if (navigator.clipboard?.writeText) {
      return navigator.clipboard.writeText(s).catch(() => legacyCopy(s));
    }
    return legacyCopy(s);
  }

  function legacyCopy(text) {
    const ta = document.createElement("textarea");
    ta.value = `${text ?? ""}`;
    ta.setAttribute("readonly", "true");
    ta.style.position = "fixed";
    ta.style.left = "-9999px";
    ta.style.top = "0";
    document.body.appendChild(ta);
    ta.focus();
    ta.select();
    try {
      document.execCommand("copy");
    } finally {
      document.body.removeChild(ta);
    }
    return Promise.resolve();
  }

  function pill(label, value, key) {
    const selected = state.selected[key]?.has(value);
    return `
      <button class="pill ${selected ? "on" : ""}" type="button" data-facet="${escapeHtml(key)}" data-value="${escapeHtml(
      value
    )}">
        <span class="dot" data-color="${escapeHtml(key === "color" ? value : "")}"></span>
        <span class="pillText">${escapeHtml(value)}</span>
        <span class="pillCount" data-count="${escapeHtml(`${label}:${value}`)}">—</span>
      </button>
    `;
  }

  function renderDrawerFacets() {
    els.facetMount.innerHTML = facetGroups
      .map((g) => {
        const values = uniqValues(g.key);
        const pills = values.length ? values.map((v) => pill(g.label, v, g.key)).join("") : `<div class="muted">（無）</div>`;
        return `
          <section class="facet">
            <div class="facetHead">
              <div class="facetTitle">${escapeHtml(g.label)}</div>
              <button class="mini" type="button" data-clear-facet="${escapeHtml(g.key)}">清除</button>
            </div>
            <div class="pillGrid">${pills}</div>
          </section>
        `;
      })
      .join("");

    els.facetMount.addEventListener("click", (e) => {
      const pillBtn = e.target.closest("button.pill[data-facet][data-value]");
      if (pillBtn) {
        const key = pillBtn.getAttribute("data-facet");
        const value = pillBtn.getAttribute("data-value");
        const set = state.selected[key];
        if (!set) return;
        if (set.has(value)) set.delete(value);
        else set.add(value);
        apply();
        return;
      }

      const clear = e.target.closest("button[data-clear-facet]");
      if (clear) {
        const key = clear.getAttribute("data-clear-facet");
        state.selected[key]?.clear?.();
        apply();
      }
    });
  }

  function renderSelectedChips() {
    const chips = [];
    for (const g of facetGroups) {
      for (const v of state.selected[g.key] || []) {
        chips.push(
          `<button class="chip" type="button" data-chip="${escapeHtml(g.key)}" data-value="${escapeHtml(v)}">
            <span class="chipKey">${escapeHtml(g.label)}</span>
            <span class="chipVal">${escapeHtml(v)}</span>
            <span class="chipX">×</span>
          </button>`
        );
      }
    }

    const minH = Number(state.minH);
    const maxH = Number(state.maxH);
    if (
      Number.isFinite(minH) &&
      Number.isFinite(maxH) &&
      (minH !== heightBounds.min || maxH !== heightBounds.max)
    ) {
      chips.push(
        `<button class="chip" type="button" data-chip="height">
          <span class="chipKey">跟高</span>
          <span class="chipVal">${escapeHtml(`${minH}-${maxH}cm`)}</span>
          <span class="chipX">×</span>
        </button>`
      );
    }

    if (state.query.trim()) {
      chips.push(
        `<button class="chip" type="button" data-chip="query">
          <span class="chipKey">搜尋</span>
          <span class="chipVal">${escapeHtml(state.query.trim())}</span>
          <span class="chipX">×</span>
        </button>`
      );
    }

    els.chipBar.innerHTML = chips.length
      ? `<div class="chipScroll">${chips.join("")}</div>`
      : `<div class="chipEmpty">沒有套用任何篩選</div>`;
  }

  function colorSwatch(colorText) {
    const c = (colorText ?? "").toString().trim();
    const map = new Map([
      ["黑", "#111827"],
      ["白", "#f9fafb"],
      ["銀", "#cbd5e1"],
      ["灰", "#9ca3af"],
      ["淺灰", "#d1d5db"],
      ["桃紅", "#ff2d86"],
      ["珊瑚粉", "#ff6b6b"],
      ["粉", "#f472b6"],
      ["紅", "#ef4444"],
      ["藍", "#3b82f6"],
      ["棕", "#8b5e3c"],
      ["米", "#e9d5a1"],
    ]);
    for (const [k, v] of map.entries()) {
      if (c.includes(k)) return v;
    }
    return "#94a3b8";
  }

  function heelGauge(h) {
    const n = Number(h);
    if (!Number.isFinite(n)) return { pct: 0, label: "—" };
    const pct = clamp((n / 15) * 100, 0, 100);
    return { pct, label: `${n}cm` };
  }

  function renderGrid(items) {
    els.grid.dataset.view = state.view;
    els.grid.innerHTML = "";

    if (!items.length) {
      els.empty.style.display = "block";
      return;
    }
    els.empty.style.display = "none";

    for (const item of items) {
      const imgSrc = (item?.image ?? "").toString();
      const objectPos = (item?.objectPosition ?? "50% 50%").toString();
      const h = heelGauge(item?.heelHeightCm);
      const sw = colorSwatch(item?.color);

      const card = document.createElement("article");
      card.className = "card";
      card.tabIndex = 0;
      card.setAttribute("data-id", item?.id ?? "");
      card.innerHTML = `
        <div class="media">
          <img src="${escapeHtml(imgSrc)}" alt="${escapeHtml(item?.filename)}" loading="lazy" style="object-position:${escapeHtml(
        objectPos
      )}" />
          <div class="fade"></div>
          <div class="badgeRow">
            <span class="badge">${escapeHtml(item?.style || "—")}</span>
            <span class="badge ghost">${escapeHtml(item?.toe || "—")}</span>
          </div>
          <div class="gauge" title="${escapeHtml(h.label)}">
            <div class="gaugeFill" style="height:${h.pct}%"></div>
          </div>
          <div class="swatch" title="${escapeHtml(item?.color || "—")}" style="background:${escapeHtml(sw)}"></div>
        </div>
        <div class="info">
          <div class="name">
            <div class="file">${escapeHtml(item?.filename || "")}</div>
            <button class="iconBtn" type="button" data-copy="${escapeHtml(item?.filename || "")}" title="複製檔名">
              <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
                <path fill="currentColor" d="M8 7a3 3 0 0 1 3-3h7a3 3 0 0 1 3 3v9a3 3 0 0 1-3 3h-7a3 3 0 0 1-3-3V7Zm3-1a1 1 0 0 0-1 1v9a1 1 0 0 0 1 1h7a1 1 0 0 0 1-1V7a1 1 0 0 0-1-1h-7Z"></path>
                <path fill="currentColor" d="M3 8a3 3 0 0 1 3-3h1a1 1 0 1 1 0 2H6a1 1 0 0 0-1 1v9a1 1 0 0 0 1 1h8a1 1 0 0 0 1-1v-1a1 1 0 1 1 2 0v1a3 3 0 0 1-3 3H6a3 3 0 0 1-3-3V8Z"></path>
              </svg>
            </button>
          </div>
          <div class="metaLine">
            <button class="tag" type="button" data-add="heelStyle" data-value="${escapeHtml(item?.heelStyle || "")}">${escapeHtml(
        item?.heelStyle || "—"
      )}</button>
            <span class="sep">•</span>
            <span class="h">${escapeHtml(h.label)}</span>
          </div>
          <div class="tagRow">
            <button class="tag" type="button" data-add="material" data-value="${escapeHtml(item?.material || "")}">${escapeHtml(
        item?.material || "—"
      )}</button>
            <button class="tag" type="button" data-add="color" data-value="${escapeHtml(item?.color || "")}">${escapeHtml(
        item?.color || "—"
      )}</button>
          </div>
        </div>
      `;

      card.addEventListener("click", (e) => {
        const copyBtn = e.target.closest("button[data-copy]");
        if (copyBtn) {
          e.stopPropagation();
          copyText(copyBtn.getAttribute("data-copy") || "");
          copyBtn.classList.add("ok");
          setTimeout(() => copyBtn.classList.remove("ok"), 450);
          return;
        }

        const addBtn = e.target.closest("button.tag[data-add][data-value]");
        if (addBtn) {
          e.stopPropagation();
          const key = addBtn.getAttribute("data-add");
          const value = addBtn.getAttribute("data-value");
          if (!value) return;
          state.selected[key]?.add?.(value);
          apply();
          return;
        }

        openModal(item);
      });

      card.addEventListener("keydown", (e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          openModal(item);
        }
      });

      els.grid.appendChild(card);
    }
  }

  function rowText(item) {
    const parts = [
      item?.filename,
      item?.style,
      item?.toe,
      item?.heelStyle,
      item?.heelHeightCm,
      item?.material,
      item?.color,
    ].map((x) => (x === null || x === undefined ? "" : `${x}`.trim()));
    return parts.join("/");
  }

  function openModal(item) {
    const imgSrc = (item?.image ?? "").toString();
    els.modalImg.src = imgSrc;
    els.modalImg.style.objectPosition = (item?.objectPosition ?? "50% 50%").toString();
    els.modalTitle.textContent = item?.filename ?? "";

    const meta = [
      ["款式", item?.style],
      ["鞋頭", item?.toe],
      ["鞋跟", item?.heelStyle],
      ["跟高", Number.isFinite(Number(item?.heelHeightCm)) ? `${item.heelHeightCm}cm` : "—"],
      ["材質", item?.material],
      ["顏色", item?.color],
    ];
    els.modalMeta.innerHTML = meta
      .map(
        ([k, v]) =>
          `<div class="kv"><div class="k">${escapeHtml(k)}</div><div class="v">${escapeHtml(v ?? "—")}</div></div>`
      )
      .join("");

    els.modalCopyName.onclick = () => copyText(item?.filename ?? "");
    els.modalCopyRow.onclick = () => copyText(rowText(item));

    els.modalAddFilters.innerHTML = facetGroups
      .map((g) => {
        const v = (item?.[g.key] ?? "").toString().trim();
        if (!v) return "";
        const on = state.selected[g.key]?.has(v);
        return `<button class="pill ${on ? "on" : ""}" type="button" data-facet="${escapeHtml(g.key)}" data-value="${escapeHtml(
          v
        )}">${escapeHtml(g.label)}：${escapeHtml(v)}</button>`;
      })
      .filter(Boolean)
      .join("");

    setModalOpen(true);
  }

  function updateCounts(filtered) {
    els.count.textContent = `${filtered.length} / ${data.length}`;

    // pill counts: compute counts under current query+height and other selected facets (excluding same facet group)
    const base = {
      query: state.query,
      minH: state.minH,
      maxH: state.maxH,
      selected: Object.fromEntries(facetGroups.map((g) => [g.key, new Set(state.selected[g.key])])),
    };

    for (const g of facetGroups) {
      // Remove the facet group to count "what would be available if you switch within this group"
      base.selected[g.key] = new Set();
      const baseItems = applyFilters(data, base);
      const counts = new Map();
      for (const it of baseItems) {
        const v = (it?.[g.key] ?? "").toString().trim();
        if (!v) continue;
        counts.set(v, (counts.get(v) ?? 0) + 1);
      }

      for (const pillEl of $$(`button.pill[data-facet="${cssEscape(g.key)}"][data-value]`, els.facetMount)) {
        const v = pillEl.getAttribute("data-value") || "";
        const n = counts.get(v) ?? 0;
        const countEl = $(".pillCount", pillEl);
        if (countEl) countEl.textContent = `${n}`;
      }

      base.selected[g.key] = new Set(state.selected[g.key]);
    }
  }

  function apply() {
    // keep range sane
    let minH = Number(els.rangeMin.value);
    let maxH = Number(els.rangeMax.value);
    if (minH > maxH) [minH, maxH] = [maxH, minH];
    state.minH = minH;
    state.maxH = maxH;

    state.query = (els.q.value ?? "").toString();

    els.rangeMinVal.textContent = `${minH}`.replace(/\.0$/, "");
    els.rangeMaxVal.textContent = `${maxH}`.replace(/\.0$/, "");

    const filtered = applyFilters(data, state);
    renderSelectedChips();
    renderGrid(filtered);
    updateCounts(filtered);

    // color swatches on pills
    for (const dot of $$(`.dot[data-color]`, document)) {
      const c = dot.getAttribute("data-color") || "";
      if (!c) continue;
      dot.style.background = colorSwatch(c);
      dot.style.borderColor = "rgba(255,255,255,.18)";
    }
  }

  function clearAll() {
    els.q.value = "";
    for (const g of facetGroups) state.selected[g.key].clear();

    const { min, max } = heightBounds;
    els.rangeMin.min = `${min}`;
    els.rangeMin.max = `${max}`;
    els.rangeMax.min = `${min}`;
    els.rangeMax.max = `${max}`;
    els.rangeMin.value = `${min}`;
    els.rangeMax.value = `${max}`;
    state.minH = min;
    state.maxH = max;
    state.query = "";
    apply();
  }

  function init() {
    const { min, max } = heightBounds;
    els.rangeMin.min = `${min}`;
    els.rangeMin.max = `${max}`;
    els.rangeMax.min = `${min}`;
    els.rangeMax.max = `${max}`;
    els.rangeMin.value = `${min}`;
    els.rangeMax.value = `${max}`;
    state.minH = min;
    state.maxH = max;

    renderDrawerFacets();

    els.q.addEventListener("input", apply);
    els.rangeMin.addEventListener("input", apply);
    els.rangeMax.addEventListener("input", apply);

    els.openFilters.addEventListener("click", () => setDrawerOpen(true));
    els.closeDrawer.addEventListener("click", () => setDrawerOpen(false));
    els.drawerOverlay.addEventListener("click", () => setDrawerOpen(false));
    els.clear.addEventListener("click", clearAll);

    els.toggleView.addEventListener("click", () => {
      state.view = state.view === "grid" ? "list" : "grid";
      els.toggleView.textContent = state.view === "grid" ? "List" : "Grid";
      apply();
    });

    els.chipBar.addEventListener("click", (e) => {
      const chip = e.target.closest("button.chip[data-chip]");
      if (!chip) return;
      const key = chip.getAttribute("data-chip");
      if (key === "height") {
        const { min, max } = heightBounds;
        els.rangeMin.value = `${min}`;
        els.rangeMax.value = `${max}`;
      } else if (key === "query") {
        els.q.value = "";
      } else {
        const value = chip.getAttribute("data-value") || "";
        state.selected[key]?.delete?.(value);
      }
      apply();
    });

    // modal wiring
    els.modalClose.addEventListener("click", () => setModalOpen(false));
    els.modalOverlay.addEventListener("click", () => setModalOpen(false));
    els.modalAddFilters.addEventListener("click", (e) => {
      const btn = e.target.closest("button.pill[data-facet][data-value]");
      if (!btn) return;
      const key = btn.getAttribute("data-facet");
      const value = btn.getAttribute("data-value");
      if (!value) return;
      const set = state.selected[key];
      if (!set) return;
      if (set.has(value)) set.delete(value);
      else set.add(value);
      apply();
      // keep modal open but update its pill states
      btn.classList.toggle("on");
    });

    // keyboard shortcuts
    window.addEventListener("keydown", (e) => {
      if (e.key === "Escape") {
        if (document.body.dataset.modalOpen === "1") setModalOpen(false);
        if (document.body.dataset.drawerOpen === "1") setDrawerOpen(false);
      }
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "f") {
        // keep browser find
        return;
      }
      if (!e.ctrlKey && !e.metaKey && e.key.toLowerCase() === "f") {
        // quick open filter drawer
        if (document.activeElement === els.q) return;
        setDrawerOpen(true);
      }
    });

    // initial
    els.toggleView.textContent = "List";
    clearAll();
  }

  init();
})();
