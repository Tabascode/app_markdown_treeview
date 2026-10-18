// Renders the markdown payload embedded in the page. Loaded as a WKUserScript after marked.umd.js.
(function () {
  "use strict";

  window.setScale = function (scale) {
    document.documentElement.style.setProperty("--scale", String(scale));
  };

  function escapeHTML(text) {
    return text.replace(/[&<>"]/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c];
    });
  }

  // GitHub style heading anchors, so "#some-heading" links work.
  function slug(text) {
    return text
      .trim()
      .toLowerCase()
      .replace(/[^\p{L}\p{N}\s_-]/gu, "")
      .replace(/\s+/g, "-");
  }

  function frontMatterHTML(frontMatter) {
    var rows = [];
    var simple = frontMatter.split("\n").every(function (line) {
      if (!line.trim()) return true;
      var match = /^([\w .-]+):\s*(.*)$/.exec(line);
      if (!match) return false;
      rows.push("<tr><th>" + escapeHTML(match[1]) + "</th><td>" + escapeHTML(match[2]) + "</td></tr>");
      return true;
    });
    var body = simple && rows.length
      ? "<table>" + rows.join("") + "</table>"
      : "<pre>" + escapeHTML(frontMatter) + "</pre>";
    return '<details class="front-matter"><summary>Metadaten</summary>' + body + "</details>";
  }

  var payloadElement = document.getElementById("payload");
  var content = document.getElementById("content");
  if (!payloadElement || !content) return;
  var payload = JSON.parse(payloadElement.textContent);
  window.setScale(payload.scale || 1);

  var html = payload.frontMatter ? frontMatterHTML(payload.frontMatter) : "";
  try {
    html += marked.parse(payload.markdown, { gfm: true, breaks: false });
  } catch (error) {
    html += "<pre>" + escapeHTML(payload.markdown) + "</pre>";
  }
  content.innerHTML = html;

  var used = {};
  content.querySelectorAll("h1, h2, h3, h4, h5, h6").forEach(function (heading) {
    var id = slug(heading.textContent) || "abschnitt";
    if (used[id] !== undefined) {
      used[id] += 1;
      id += "-" + used[id];
    } else {
      used[id] = 0;
    }
    heading.id = id;
  });

  content.querySelectorAll("li > input[type=checkbox]").forEach(function (box) {
    box.disabled = true;
    box.parentElement.classList.add("task");
  });

  content.querySelectorAll("table").forEach(function (table) {
    if (table.closest(".front-matter")) return;
    var wrapper = document.createElement("div");
    wrapper.className = "table-scroll";
    table.parentNode.insertBefore(wrapper, table);
    wrapper.appendChild(table);
  });

  document.addEventListener("click", function (event) {
    var link = event.target.closest("a[href]");
    if (!link) return;
    var href = link.getAttribute("href");
    event.preventDefault();
    if (href.charAt(0) === "#") {
      var target = document.getElementById(decodeURIComponent(href.slice(1)));
      if (target) target.scrollIntoView({ behavior: "smooth", block: "start" });
      return;
    }
    window.webkit.messageHandlers.link.postMessage(href);
  });
})();
