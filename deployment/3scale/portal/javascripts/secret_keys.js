function toggleVisibility(key_id) {
  var keyElement = document.getElementById(key_id);
  var button = event.target;

  if (keyElement.type === "password") {
    keyElement.type = "text";
  } else {
    keyElement.type = "password";
  }
}

function copyToClipboard(key_id, type) {
  var keyElement = document.getElementById(key_id);

  // Create a temporary textarea element to copy the content
  var tempTextarea = document.createElement("textarea");
  if (keyElement.tagName === "INPUT") {
    tempTextarea.value = keyElement.value.trim();
  } else {
    tempTextarea.value = keyElement.innerText.trim();
  }
  document.body.appendChild(tempTextarea);
  tempTextarea.select();
  document.execCommand("copy");
  document.body.removeChild(tempTextarea);

  alert(type+" copied to clipboard!");
}