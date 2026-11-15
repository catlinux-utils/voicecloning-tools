{
  # OmniVoice TTS on Vulkan via audio.cpp — no CUDA, no ROCm, no Python.
  #
  #   nix run . -- --text "Hello" --out out.wav          # TTS (q8_0 model)
  #   nix run .#omnivoice-server                          # WebUI at http://127.0.0.1:8080
  #   nix build .#omnivoice-f16                           # another precision
  #
  # All artifacts (Linux runtime tarball + GGUF weights) are fetched from the
  # pinned URLs and SRI hashes in versions.json — same values setup.ps1 and
  # setup.sh verify. The GPU driver provides Vulkan (mesa RADV is enough for
  # AMD); nothing else is needed.
  #
  # x86_64-linux only: that is the only prebuilt audio.cpp Linux target.

  description = "OmniVoice zero-shot TTS on Vulkan (audio.cpp), checksum-pinned";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      versions = builtins.fromJSON (builtins.readFile ./versions.json);

      # audio.cpp portable Vulkan build for Linux, auto-patched for the Nix
      # runtime (interpreter, libstdc++/libgcc, libvulkan).
      audiocpp = pkgs.stdenv.mkDerivation {
        pname = "audiocpp-vulkan";
        version = versions.audio_cpp.version;
        src = pkgs.fetchurl {
          inherit (versions.audio_cpp.assets.linux-x64) url;
          hash = versions.audio_cpp.assets.linux-x64.sri;
        };
        nativeBuildInputs = [ pkgs.autoPatchelfHook pkgs.makeWrapper ];
        buildInputs = with pkgs; [ stdenv.cc.cc.lib vulkan-loader ];
        dontConfigure = true;
        dontBuild = true;
        dontStrip = true;
        unpackPhase = ''
          runHook preUnpack
          mkdir unpacked
          tar xzf $src -C unpacked
          runHook postUnpack
        '';
        installPhase = ''
          runHook preInstall
          mkdir -p $out
          # handle both flat tarballs and ones with a top-level directory
          if [ -f unpacked/audiocpp_server ]; then
            cp -r unpacked/. $out/
          else
            cp -r unpacked/*/  $out/
          fi
          runHook postInstall
        '';
        meta = with pkgs.lib; {
          description = "audio.cpp pure C++ audio inference engine (Vulkan portable build)";
          homepage = "https://github.com/0xShug0/audio.cpp";
          license = licenses.asl20;
          platforms = [ system ];
        };
      };

      # Model directory laid out like models/OmniVoice-GGUF in a store path.
      gguf = precision:
        let spec = versions.omnivoice_gguf.precision.${precision}; in
        pkgs.runCommand "omnivoice-${precision}-gguf" { } ''
          mkdir -p "$out/${versions.omnivoice_gguf.dir}"
          ln -s ${
            pkgs.fetchurl {
              inherit (spec) url;
              hash = spec.sri;
            }
          } "$out/${versions.omnivoice_gguf.dir}/${spec.filename}"
        '';

      modelPath = precision: "${gguf precision}/${versions.omnivoice_gguf.dir}";

      # CLI wrapper: `omnivoice` with OmniVoice defaults, `audiocpp-cli` as a
      # raw passthrough for everything else audio.cpp supports.
      cli = precision:
        pkgs.runCommand "omnivoice-cli-${precision}"
          {
            nativeBuildInputs = [ pkgs.makeWrapper ];
            meta = {
              description = "OmniVoice TTS on Vulkan (audio.cpp, ${precision} GGUF)";
              platforms = [ system ];
            };
          } ''
          mkdir -p $out/bin
          makeWrapper ${audiocpp}/audiocpp_cli $out/bin/omnivoice \
            --add-flags "--task tts --family omnivoice --backend vulkan --model ${modelPath precision}"
          makeWrapper ${audiocpp}/audiocpp_cli $out/bin/audiocpp-cli
        '';

      server = precision:
        let
          config = pkgs.writeText "omnivoice-server.json" (builtins.toJSON {
            host = "127.0.0.1";
            port = 8080;
            backend = "vulkan";
            device = 0;
            threads = 4;
            lazy_load = true;
            max_loaded_models = 1;
            ui = true;
            ui_management = false;
            models = [{
              id = "omnivoice";
              family = "omnivoice";
              path = modelPath precision;
              task = "tts";
              mode = "offline";
              default_request_options = {
                num_inference_steps = 32;
                guidance_scale = 2.0;
                speed = 1.0;
              };
            }];
          });
        in
        pkgs.runCommand "omnivoice-server-${precision}"
          {
            nativeBuildInputs = [ pkgs.makeWrapper ];
            meta = {
              description = "OmniVoice WebUI + OpenAI-compatible server on Vulkan (${precision})";
              platforms = [ system ];
            };
          } ''
          mkdir -p $out/bin
          makeWrapper ${audiocpp}/audiocpp_server $out/bin/omnivoice-server \
            --add-flags "--config ${config}"
        '';

    in
    {
      packages.${system} = {
        audiocpp-vulkan = audiocpp;
        default = cli "q8_0";
        omnivoice-q8_0 = cli "q8_0";
        omnivoice-bf16 = cli "bf16";
        omnivoice-f16 = cli "f16";
        omnivoice-server = server "q8_0";
      };

      apps.${system} = {
        default = {
          type = "app";
          program = "${cli "q8_0"}/bin/omnivoice";
          meta.description = "OmniVoice TTS on Vulkan";
        };
        omnivoice-server = {
          type = "app";
          program = "${server "q8_0"}/bin/omnivoice-server";
          meta.description = "OmniVoice WebUI + OpenAI-compatible server";
        };
      };
    };
}
