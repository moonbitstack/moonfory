/* The byte tape and the copy buttons. No framework, no tracking, no network. */

(function () {
  "use strict";

  var samples = {
    int: {
      hex: "01ff042a000000",
      decode:
        "<b>INT32</b> — head <code>01</code>, NOT_NULL <code>ff</code>, type <code>04</code>, then <code>2a 00 00 00</code> = 42 little-endian.",
    },
    str: {
      hex: "01ff150a6162",
      decode:
        "<b>STRING</b> — type <code>15</code>, header <code>0a</code> = (2 &lt;&lt; 2) | UTF-8, then <code>61 62</code> = \"ab\".",
    },
    bool: {
      hex: "01ff0101",
      decode:
        "<b>BOOL</b> — type <code>01</code>, then one byte: <code>01</code> is true.",
    },
    float: {
      hex: "01ff14000000000000f83f",
      decode:
        "<b>FLOAT64</b> — type <code>14</code>, then the IEEE 754 bits of 1.5, little-endian.",
    },
    list: {
      hex: "01ff16030804010000000200000003000000",
      decode:
        "<b>LIST</b> — count 3, element header <code>08</code> (all the same type), element type <code>04</code> (INT32), then three little-endian ints.",
    },
    map: {
      hex: "01ff180100011504066101000000",
      decode:
        "<b>MAP</b> — total 1, chunk header <code>00</code>, chunk size 1, key STRING, value INT32, then the pair.",
    },
  };

  var hexEl = document.getElementById("hex");
  var decodeEl = document.getElementById("decode");
  var picker = document.getElementById("picker");

  function render(key) {
    var s = samples[key];
    if (!s || !hexEl) return;
    var bytes = s.hex.match(/.{2}/g) || [];
    hexEl.innerHTML = "";
    bytes.forEach(function (b, i) {
      var span = document.createElement("span");
      span.textContent = b;
      // head and flag in oxide, the type id in teal, the body in ink.
      if (i < 2) span.className = "t0";
      else if (i === 2) span.className = "t1";
      else span.className = "t2";
      hexEl.appendChild(span);
    });
    if (decodeEl) decodeEl.innerHTML = s.decode;
  }

  if (picker) {
    picker.addEventListener("click", function (e) {
      var btn = e.target.closest("button[data-key]");
      if (!btn) return;
      Array.prototype.forEach.call(
        picker.querySelectorAll("button[data-key]"),
        function (b) {
          b.setAttribute("aria-pressed", b === btn ? "true" : "false");
        }
      );
      render(btn.getAttribute("data-key"));
    });
    render("int");
  }

  // Copy buttons beside each code block.
  Array.prototype.forEach.call(
    document.querySelectorAll("[data-copy]"),
    function (btn) {
      btn.addEventListener("click", function () {
        var block = btn.closest(".code");
        var pre = block && block.querySelector("pre");
        if (!pre) return;
        var text = pre.innerText;
        var done = function () {
          var old = btn.textContent;
          btn.textContent = "copied";
          setTimeout(function () {
            btn.textContent = old;
          }, 1400);
        };
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(text).then(done, function () {});
        } else {
          var ta = document.createElement("textarea");
          ta.value = text;
          ta.style.position = "fixed";
          ta.style.opacity = "0";
          document.body.appendChild(ta);
          ta.select();
          try {
            document.execCommand("copy");
            done();
          } catch (e) {
            /* nothing left to offer */
          }
          document.body.removeChild(ta);
        }
      });
    }
  );
})();
