function showHideDiv(divname) {
  var currentDiv = document.getElementById(divname);
  var appButton = document.getElementById('show_' + divname);
  if(currentDiv.style.display === "none") {
    currentDiv.style.display = "block";
    appButton.innerHTML = "Hide Details";
  } else {
    currentDiv.style.display = "none";
    appButton.innerHTML = "Show Details";
  }
}