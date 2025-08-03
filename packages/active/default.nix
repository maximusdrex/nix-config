{
  lib,
  appimageTools,
  fetchurl,
}:

let
  version = "4.15";
  pname = "active-firmware-tools";

  src = fetchurl {
    url = "https://drive.google.com/uc?id=18-jqKV4BOi86tcR9S6j8wrat5Gq250UR";
    hash = "sha256-c/0jXnyC7N5r7VJH6tEUdJZnWd0PCES5CwqL4V673LM=";
  };

  appimageContents = appimageTools.extractType1 { inherit pname src; };
in
appimageTools.wrapType2 rec {
  inherit pname version src;

  extraInstallCommands = ''
    mkdir -p $out/share/applications
    cat <<INI > $out/share/applications/${pname}.desktop 
    [Desktop Entry]
    Type=Application
    Name=Active-Pro Firmware Debugger
    Comment=Active-Pro Firmware Debugger
    Exec=$out/bin/${pname} %f
    Icon=/home/max/Setup/active/besticon.png
    Categories=Office;
    X-AppImage-Version=

    INI
  '';

  meta = {
    mainProgram = pname;
    description = "Active-Pro Firmware Debugger";
    homepage = "https://www.activefirmwaretools.com";
    downloadPage = "https://www.activefirmwaretools.com/download";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
  };
}
