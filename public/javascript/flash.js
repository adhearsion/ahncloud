function showFlash(type) {
  var flash_div = document.getElementById('flash');
  flash_div.style.display = "block";
  if(type === "notice") {
    flash_div.className = "ui-state-highlight";
  }
  else if(type === "error") {
    flash_div.className = "ui-state-error";
  }
  else {
    hideFlash();
  }
}

function hideFlash() {
  var flash_div = document.getElementById('flash');
  flash_div.style.display = "none";
}

  

