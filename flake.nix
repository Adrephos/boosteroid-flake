{
  description = "A Nix Flake for the Boosteroid client";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config = {
              allowUnfree = true;
            };
          };
        in
        {
          boosteroid = pkgs.stdenv.mkDerivation {
            pname = "boosteroid";
            version = "1.10.14";

            # The upstream URL is always-latest; the version above must be kept
            # in sync manually or via `nix-update boosteroid`.
            src = pkgs.fetchurl {
              curlOpts = "--user-agent 'Mozilla/5.0'";
              url = "https://boosteroid.com/linux/installer/boosteroid-install-x64.deb";
              hash = "sha256-7OXM3ib02cC9LNHrwq5YvpE9oWwM1PgH+MaSlo13ei8=";
            };

            nativeBuildInputs = with pkgs; [
              autoPatchelfHook
              dpkg
              makeWrapper
            ];

            buildInputs = with pkgs; [
              xcbutil
              libxcb
              numactl
              libva
              libvdpau
              libXfixes
              libXi
              systemd
              alsa-lib
              libX11
              xcbutilwm
              xcbutilimage
              xcbutilkeysyms
              xcbutilrenderutil
              libxkbcommon
              freetype
              fontconfig
              wayland
              qt5.qtwayland # Wayland QPA plugin; Boosteroid may ship its own Qt — remove if conflicts arise
              pcre2
              dbus
              libpulseaudio
              libGL
              xz
              libinput
              libXcursor
              libXrandr
              libXinerama
              libXrender
              libXtst
              libxkbfile
            ];

            sourceRoot = ".";
            unpackCmd = "dpkg-deb -x $src .";

            dontConfigure = true;
            dontBuild = true;
            dontWrapQtApps = true;

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
                --set-default QT_QPA_PLATFORM "xcb" \
                --prefix XCURSOR_PATH : "$out/share/icons" \
                --prefix XDG_DATA_DIRS : "$out/share" \
                --set-default QT_XCB_GL_INTEGRATION "xcb_egl" \
                --set-default QT_QPA_PLATFORMTHEME "qt5ct"
              runHook postInstall
            '';

            passthru.updateScript = pkgs.nix-update-script { };

            meta = with pkgs.lib; {
              description = "Boosteroid cloud gaming client";
              homepage = "https://boosteroid.com/";
              license = licenses.unfree;
              platforms = platforms.linux;
              mainProgram = "Boosteroid";
            };
          };
          default = self.packages.${system}.boosteroid;
        }
      );

      apps = forAllSystems (system: {
        boosteroid = {
          type = "app";
          program = "${self.packages.${system}.boosteroid}/bin/Boosteroid";
        };
        default = self.apps.${system}.boosteroid;
      });

      nixosModules.default =
        { config, pkgs, lib, ... }:
        let
          cfg = config.programs.boosteroid;
          decoderFlag = {
            vdpau    = "-vdpau";
            vaapi    = "-vaapi";
            cuda     = "-cuda";
            software = "-s";
            default  = null;
          }.${cfg.videoDecoder};

          needsWrapper = decoderFlag != null || cfg.extraEnv != { };

          wrapperArgs = lib.concatStringsSep " " (
            lib.optional (decoderFlag != null) "--add-flags ${lib.escapeShellArg decoderFlag}"
            ++ lib.mapAttrsToList
              (k: v: "--set-default ${k} ${lib.escapeShellArg v}")
              cfg.extraEnv
          );

          finalPackage =
            if !needsWrapper then cfg.package
            else pkgs.symlinkJoin {
              name = "boosteroid-wrapped";
              paths = [ cfg.package ];
              buildInputs = [ pkgs.makeWrapper ];
              postBuild = "wrapProgram $out/bin/Boosteroid ${wrapperArgs}";
            };
        in
        {
          options.programs.boosteroid = {
            enable = lib.mkEnableOption "Boosteroid cloud gaming client";
            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.system}.boosteroid;
              defaultText = lib.literalExpression "boosteroid";
              description = "The Boosteroid package to use.";
            };
            videoDecoder = lib.mkOption {
              type = lib.types.enum [ "default" "vdpau" "vaapi" "cuda" "software" ];
              default = "default";
              description = ''
                Video decoder for stream playback.
                "vdpau" and "vaapi" use hardware acceleration; "cuda" requires NVIDIA;
                "software" disables hardware decoding; "default" lets Boosteroid choose.
              '';
            };
            extraEnv = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              example = {
                LIBVA_DRIVER_NAME = "radeonsi";
                LIBVA_DRIVERS_PATH = "/run/opengl-driver/lib/dri";
                LD_LIBRARY_PATH = "/run/opengl-driver/lib";
              };
              description = ''
                Extra environment variables passed to Boosteroid at launch via
                --set-default, so they can still be overridden from the shell.
                Useful for VAAPI tuning: set LIBVA_DRIVER_NAME (e.g. "radeonsi",
                "nvidia", "iHD"), LIBVA_DRIVERS_PATH, and LD_LIBRARY_PATH.
              '';
            };
          };

          config = lib.mkIf cfg.enable {
            environment.systemPackages = [ finalPackage ];
          };
        };
    };
}
