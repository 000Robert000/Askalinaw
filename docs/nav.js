// Shared header + navigation for every page.
(function () {
  var pages = [
    ["index.html", "Summary"], ["infrastructure.html", "AWS design"], ["system.html", "System & card"],
    ["baseline.html", "Baseline"], ["well-architected.html", "Well-Architected"],
    ["operations.html", "Monitoring · Backup · Security"], ["incident.html", "Automation & incident"],
    ["results.html", "Results & next steps"], ["declaration.html", "Declaration"]
  ];
  var here = location.pathname.split("/").pop() || "index.html";
  var links = pages.map(function (p) {
    return '<a href="' + p[0] + '"' + (p[0] === here ? ' class="on"' : "") + ">" + p[1] + "</a>";
  }).join("");
  document.body.insertAdjacentHTML("afterbegin",
    '<header class="site"><img src="img/logo.svg" alt="Askalinaw logo"><strong>Askalinaw</strong>' +
    '<span>SAM10 Final Project · Robert Santiago &amp; Ivan Ray Dequiros</span></header>' +
    '<nav class="site">' + links + "</nav>");
  document.body.insertAdjacentHTML("beforeend",
    "<footer>Askalinaw is a SAM10 student project built on LibreChat (MIT licence, Danny Avila). " +
    "Kalinaw University is fictional; all data is invented.</footer>");
})();
