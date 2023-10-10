# FPHC

Combines the SHA3-512 hashes of a file(s) and a password by the user multi-threaded.
Primarily written to thwart Evil Maid attacks on boot from Initramfs.

## How is this supposed to prevent an Evil Maid attack?
The intended use is the following:
- create a key from all the unencrypted files and a user specified password
- enroll this key in a LUKS partition
- during boot, use a hook (W.I.P.) to perform step 1. and create a keyfile to unlock the partition from step 2

If any files change, the resulting key will be invalid
If none of the files have changed, but a bad password was supplied, the key will be invalid
If none of the files have changed and a valid password was supplied, the key will be valid

## How to build:
At least Zig master (0.12.0-dev.706+62a0fbdae) is required
1. Clone the repo: `git clone https://github.com/spflaumer/fphc.git`
2. Change directory into the repo: `cd fphc`
3. Initialize submodules: `git submodule update --init --recursive`
4. Run the build command: `zig build`
5. The output file will be within `zig-out/bin`

## Things that need fixing:
- password is echoed onto the terminal
- only files can be currently supplied for hashing. implement hashing of directories
- probably make a switch to a thread pool, rather than creating separate threads
