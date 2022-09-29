module DataType::DataType {
    use std::signer;
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

    #[test(account = @0x01010101010101010101)]
    fun test_address(account: signer) {
        let a: address = @0x01;
        let b: address = @0x00000000000000000000000000000001;

        assert!(a == b, 0);

        // address copyable
        let c = b;
        assert!(a == c, 0);
        // name address
        let _: address = @std;

        let d: address = @0x01010101010101010101;
        assert!(d == signer::address_of(&account), 0);

    }
}
