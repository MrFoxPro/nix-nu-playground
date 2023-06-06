let dervs = [ nuenv-drv rust-drv stdenv-drv ]
print ("Will build: " + ($dervs | str join " "))
for drv in $dervs { nu -c $"nix build .#packages.x86_64-linux.($drv) --print-build-logs" }