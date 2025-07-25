{
  description = "A Nix Flake for the Boosteroid client";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            system = system;
            config = { allowUnfree = true; };
          };
        in
        {
          boosteroid = pkgs.stdenv.mkDerivation {
            pname = "boosteroid";
            version = "1.9.28-beta";

            src = pkgs.fetchurl {
              curlOpts = "--user-agent 'Mozilla/5.0'";
              url = "https://boosteroid.com/linux/installer/boosteroid-install-x64.deb";
              hash = "sha256-HXHH5AcNz0jiy1zfOJO2iqf6Tj12dIO0NcDWs/yMMOo=";
            };

            nativeBuildInputs = with pkgs; [
              autoPatchelfHook
              dpkg
              makeWrapper
            ];

            buildInputs = with pkgs; [
              xorg.xcbutil
              xorg.libxcb
              numactl
              libva
              libvdpau
              xorg.libXfixes
              xorg.libXi
              systemd
              alsa-lib
              xorg.libX11
              xorg.xcbutilwm
              xorg.xcbutilimage
              xorg.xcbutilkeysyms
              xorg.xcbutilrenderutil
              libxkbcommon
              freetype
              fontconfig
              wayland-scanner
              pcre2
              dbus
              libpulseaudio
              libGL
              xz
              libinput
              xorg.libXcursor
              xorg.libXrandr
              xorg.libXinerama
              xorg.libXrender
              xorg.libXtst
              xorg.libxkbfile
            ];

            sourceRoot = ".";
            unpackCmd = "dpkg-deb -x $src .";

            dontConfigure = true;
            dontBuild = true;

            installPhase = ''
              runHook preInstall
              install -m755 -D opt/BoosteroidGamesS.R.L./bin/Boosteroid $out/bin/Boosteroid
              cp -R usr/share $out/
              cp -R usr/local $out/
              cp -R opt/BoosteroidGamesS.R.L./lib $out/
              substituteInPlace $out/share/applications/Boosteroid.desktop \
                --replace-warn /opt/BoosteroidGamesS.R.L./bin $out/bin \
                --replace-warn Icon=/usr/share/icons/Boosteroid/icon.svg Icon=$out/share/icons/Boosteroid/icon.svg
              wrapProgram "$out/bin/Boosteroid" \
                --set QT_QPA_PLATFORM "xcb" \
                --set XCURSOR_PATH "$out/share/icons:$XCURSOR_PATH" \
                --set XCURSOR_THEME "YourCursorTheme" \
                --set XDG_DATA_DIRS "$out/share:$XDG_DATA_DIRS" \
                --set QT_XCB_GL_INTEGRATION "xcb_egl" \
                --set QT_QPA_PLATFORMTHEME "qt5ct"
              runHook postInstall
            '';

            meta = with pkgs.lib; {
              description = "Boosteroid cloud gaming client";
              homepage = "https://boosteroid.com/";
              license = licenses.unfree;
              platforms = platforms.linux;
            };
          };
          default = self.packages.${system}.boosteroid;
        });

      apps = forAllSystems (system: {
        boosteroid = {
          type = "app";
          program =
            "${self.packages.${system}.boosteroid}/bin/Boosteroid";
        };
        default = self.apps.${system}.boosteroid;
      });
    };
}
