{ lib
, requireFile
, stdenvNoCC
, unzip
, variant ? "ligaturesoff-0variant1-7variant0"
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "berkeley-mono";
  version = "1.009";

  src = requireFile rec {
    name = "${finalAttrs.pname}-${finalAttrs.version}.zip";
    sha256 = "0b3xaqwcckcs4xy6a17qdlbry7cshqdy8jzhprqvar0v7xv83z6r";
    message = ''
      This file needs to be manually downloaded from the Berkeley Graphics
      site (https://berkeleygraphics.com/accounts). An email will be sent to
      get a download link.

      Select the variant that matches “${variant}”
      & download the zip file.

      Then run:

      mv \$PWD/berkeley-mono-typeface.zip \$PWD/${name}
      nix-prefetch-url --type sha256 file://\$PWD/${name}
    '';
  };

  meta = {
    description = "Berkeley Mono Typeface";
    longDescription = "…";
    homepage = "https://berkeleygraphics.com/typefaces/berkeley-mono";
    license = lib.licenses.unfree;
    platforms = lib.platforms.all;
  };

  nativeBuildInputs = [
    unzip
  ];

  unpackPhase = ''
    unzip $src
  '';

  installPhase = ''
    runHook preInstall

    install -D -m444 -t $out/share/fonts/truetype */*/*.ttf

    runHook postInstall
  '';

})
