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

## Things that need fixing:
- password is echoed onto the terminal
- only files can be currently supplied for hashing. implement hashing of directories
- probably make a switch to a thread pool, rather than creating separate threads