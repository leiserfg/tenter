{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
{
  android = {
    enable = true;
    platforms.version = [ "34" ];
    systemImageTypes = [ ];
    abis = [ "arm64-v8a" ];

    emulator = {
      enable = false;
    };
    sources.enable = false;
    systemImages.enable = true;
    ndk.enable = true;
    googleAPIs.enable = true;
    googleTVAddOns.enable = false;
    android-studio.enable = false;
    flutter.enable = true;
  };
}
