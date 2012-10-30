$("#phono").css("width", "210px").css("top", $("#apps").offset().top).css("left", $("#apps").offset().left + 480)
  .callme({
    apiKey: "c065e8cc19d386d73cbfdd61293ed4c6",
    numberToDial: "sip:wdrexler@sip2sip.info",
    buttonTextReady: "Call",
    slideOpen: true
  });