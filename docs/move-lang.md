# move language book

https://move-language.github.io/move/modules-and-scripts.html

### module and scripts
module: data type and code stored in global storage
script: temporary code executed like main method in other language. 
script cannot declare friends, structure types or access global storage

a move source file could include some modules and scripts.


account address
name address 
name address will be replaced by account address after compilation 
global storage

### bool and integers
u8, u64, u128 and true and false

### address
address is 128 bit identifier, build-in type.
cannot be created from integers, they do not support arithmetic operations, and they cannot be modified.

access to global storage.
exists, borrow_global, borrow_global_mut, and move_from

### Vector

### signer
build-in type, on behalf of an address. 
signer can't be created, except the Move VM.

### References

### struct and resource
struct values as resources if they cannot be copied and cannot be dropped.



Scripts. 