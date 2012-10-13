function showHideDiv(divname) {
  var currentDiv = document.getElementById(divname);
  if(currentDiv.style.display === "none") {
    currentDiv.style.display = "block";
  } else {
    currentDiv.style.display = "none";
  }
}