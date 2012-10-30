function phono()
{
  $("#phono").css("width", "210px").css("top", $("#apps").offset().top).css("left", $("#apps").offset().left + 480);
  var callme = $("#phono").callme({
      apiKey: "c065e8cc19d386d73cbfdd61293ed4c6",
      numberToDial: $("#dialOptions").val(),
      buttonTextReady: "Call",
      slideOpen: true
    });
}
phono();
$(window).resize(function() {
  $("#phono").css("top", $("#apps").offset().top).css("left", $("#apps").offset().left + 480);
});
$("#dialOptions").change(function() {
  $(".phono-hldr").remove();
  phono();
});