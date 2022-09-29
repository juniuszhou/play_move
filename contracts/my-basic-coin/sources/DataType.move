module DataType::DataType {
    use std::signer;
    use std::vector;
    struct Data has drop {}

    #[test]
    fun test_integer() {
        let a = 1u8;
        let b = 2u8;
        let c = 255u8;
        let d = 1025u64;

        assert!(a + 1 == b, 0);
        assert!(d == d, 0);

        // bit operation
        assert!(a & c == a, 0);

        // TODO how to check exception like overflow
        // assert!(b + c == a, 0);

        // exception when casting
        // assert!((d as u8) == a, 0);
       
    }

    #[test(account = @0x0101)]
    fun test_address(account: signer) {
        let a: address = @0x01;
        let b: address = @0x00000000000000000000000000000001;

        assert!(a == b, 0);

        // address copyable
        let c = b;
        assert!(a == c, 0);
        // name address
        let _: address = @std;

        let d: address = @0x0101;
        assert!(d == signer::address_of(&account), 0);

    }

    #[test]
    fun test_vector() {
        let a = vector::empty<u8>();
        assert!(a == vector::empty<u8>(), 0);
        vector::push_back(&mut a, 1);
        assert!(a == vector::singleton<u8>(1), 0);

        // copy vector, vector is copyable if item is copyable.
        let b = copy a;
        assert!(b == vector::singleton<u8>(1), 0);

        // hex string usage
        assert!(b"" == x"", 0);
        assert!(b"Hello!\n" == x"48656C6C6F210A", 1);
        assert!(b"\x48\x65\x6C\x6C\x6F\x21\x0A" == x"48656C6C6F210A", 2);
        assert!(
            b"\"Hello\tworld!\"\n \r \\Null=\0" ==
                x"2248656C6C6F09776F726C6421220A200D205C4E756C6C3D00",
            3
        );

    }
}
