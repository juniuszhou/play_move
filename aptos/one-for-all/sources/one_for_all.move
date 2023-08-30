/* 
    This quest features a module that can be used for creating resource accounts to be used by 
    multiple accounts. These common resource accounts can be used by multiple accounts to share
    resources and privileges. 

    Key Concepts: 
        - Resource accounts
        - Capabilities
*/
module overmind::common_accounts {
    //==============================================================================================
    // Dependencies 
    //==============================================================================================
    use std::signer;
    use std::signer::address_of;
    use std::vector;
    use aptos_framework::event::{Self, emit_event};
    use aptos_framework::account::{Self, SignerCapability, create_resource_account,
        create_signer_with_capability, create_resource_address
    };
    #[test_only]
    use aptos_std::debug::print;

    //==============================================================================================
    // Constants - DO NOT MODIFY
    //==============================================================================================    

    // seed for the module's resource account
    const SEED: vector<u8> = b"common accounts";
    
    //==============================================================================================
    // Error codes - DO NOT MODIFY
    //
    // Use this error code for all aborts
    //==============================================================================================
    const ECodeForAllErrors: u64 = 10289735;

    //==============================================================================================
    // Module Structs - DO NOT MODIFY
    //==============================================================================================

    /* 
        A resource that holds the signer capability of the common account. To be owned by the common 
        account
    */
    struct CommonAccount has key {
        // The signer capability for the common account
        signer_cap: SignerCapability,
    }

    /* 
        A resource that holds all of the management information for a common account. To be owned by 
        the common account
    */ 
    struct Management has key {
        // The address of the admin account
        admin: address,
        // List of addresses that can claim the common account's capability
        unclaimed_capabilities: vector<address>,
    }

    /* 
        The one time capability that lets the holder acquire the signer of the associated common 
        account
    */ 
    struct Capability has drop, key {
        // address of the common account the capability is for
        common_account: address,
    }

    /* 
        A resource that holds the resource account's signer cap as well as the module's events. To 
        be owned by the resource account
    */     
    struct State has key {
        // signer cap of the module's resource account
        signer_cap: SignerCapability, 
        // events
        create_common_account_events: event::EventHandle<CreateCommonAccountEvent>, 
        add_account_to_management_events: event::EventHandle<AddAccountToManagementEvent>, 
        remove_account_from_manangement_events: event::EventHandle<RemoveAccountFromManagementEvent>, 
        claim_capability_events: event::EventHandle<ClaimCapabilityEvent>, 
        acquire_signer_events: event::EventHandle<AcquireSignerEvent>
    }

    //==============================================================================================
    // Event structs - DO NOT MODIFY
    //==============================================================================================

    /* 
        Event to be emitted when a common account is created in the create_common_account function
    */
    struct CreateCommonAccountEvent has store, drop {
        // address of the account creator
        creator: address, 
        // address of the new common account
        common_account: address
    }

    /* 
        Event to be emitted when an account is added to a common account's list of users in the
        add_account function
    */
    struct AddAccountToManagementEvent has store, drop {
        // address of the common account
        common_account: address, 
        // address being added to the common account's list of users
        added_account: address
    }

    /* 
        Event to be emitted when an account is removed from a common account's list of users in the
        remove_account function
    */
    struct RemoveAccountFromManagementEvent has store, drop {
        // address of the common account
        common_account: address, 
        // address being removed from the common account's list of users
        removed_account: address
    }

    /* 
        Event to be emitted when a common account's capability is claimed in the claim_capability
        function
    */
    struct ClaimCapabilityEvent has store, drop {
        // address of the common account
        common_account: address, 
        // address of the account claiming the common account's capability
        claimer: address
    }

    /* 
        Event to be emitted when a capability is exchanged for a common account's signer in the
        acquire_signer function
    */
    struct AcquireSignerEvent has store, drop {
        // address of the common account
        common_account: address, 
        // address of the account acquiring the common account's signer
        acquirer: address
    }

    //==============================================================================================
    // Functions
    //==============================================================================================

    /* 
        Initializes the module by creating the resource account signer and creating and moving the 
        State resource to the resource account
        @param admin - signer representing the module publisher
    */
    fun init_module(admin: &signer) {
        // TODO: Create the module's resource account with the admin signer and provided SEED const
        let (resource_account_signer, signer_cap) = create_resource_account(admin, SEED);
        // TODO: Create a State object and move it to the resource account
        let state = State {
            signer_cap,
            // events
            create_common_account_events: account::new_event_handle<CreateCommonAccountEvent>(admin),
            add_account_to_management_events: account::new_event_handle<AddAccountToManagementEvent>(admin),
            remove_account_from_manangement_events: account::new_event_handle<RemoveAccountFromManagementEvent>(admin),
            claim_capability_events: account::new_event_handle<ClaimCapabilityEvent>(admin),
            acquire_signer_events: account::new_event_handle<AcquireSignerEvent>(admin)
        };
        move_to(&resource_account_signer, state);
    }

    /* 
		Create and initialize a new resource account with the CommonAccount and Management 
        resources with the provided creator and seed. Abort if the account already exists.
		@param creator - signer representing the account to create the resource account with and to 
                            set as the admin of the common account
		@param seed - seed to use when creating the new resource account
    */
    public entry fun create_common_account(
        creator: &signer, 
        seed: vector<u8>
    ) acquires State {
        assert!(!exists<CommonAccount>(create_resource_address(&address_of(creator), seed)), ECodeForAllErrors);

        let (resource_account_signer, signer_cap) = create_resource_account(creator, seed);
        let state = borrow_global_mut<State>(account::create_resource_address(&@overmind, SEED));
        let common_account = CommonAccount {
            signer_cap
        };
        move_to(&resource_account_signer, common_account);
        let management = Management {
            admin: signer::address_of(creator),
            unclaimed_capabilities: vector::empty(),
        };
        move_to(&resource_account_signer, management);
        emit_event(&mut state.create_common_account_events, CreateCommonAccountEvent {
            creator: signer::address_of(creator),
            common_account: signer::address_of(&resource_account_signer)
        });
    }

    /* 
		Add a new account to an existing common account's list of unclaimed_capabilities. This 
        function can only be called by the common account's admin. Abort if the common account 
        doesn't exist, isn't initialized with a CommonAccount and Management resource, the admin 
        isn't the common account's admin, or the claimer is already in the list.
		@param admin - signer representing the common account's admin
		@param common_account - the address of the common account to add the claimer to
		@param claimer - the address of the account to be added to the common account's 
                            unclaimed_capabilities list
    */ 
    public entry fun add_account(
        admin: &signer,
        common_account: address,
        claimer: address,
    ) acquires State, Management {
        assert!(account::exists_at(common_account), ECodeForAllErrors);
        assert!(exists<CommonAccount>(common_account), ECodeForAllErrors);
        assert!(exists<Management>(common_account), ECodeForAllErrors);

        let management = borrow_global_mut<Management>(common_account);
        assert! ((management.admin == address_of(admin)) && !vector::contains(&management.unclaimed_capabilities, &claimer), ECodeForAllErrors);
        vector::push_back(&mut management.unclaimed_capabilities, claimer);
        let state = borrow_global_mut<State>(account::create_resource_address(&@overmind, SEED));
        emit_event(&mut state.add_account_to_management_events, AddAccountToManagementEvent {
            common_account,
            added_account: claimer
        })
    }

    /* 
		Remove an account from a common account's list of unclaimed_capabilities. This function can 
        only be called by the common account's admin. Abort if the common account doesn't exist, 
        isn't initialized with a CommonAccount and Management resource, the admin isn't the common 
        account's admin, or the claimer isn't in the list.
		@param admin - signer representing the common account's admin
		@param common_account - the address of the common account to remove the claimer from
		@param claimer - the address of the account to be removed from the common account's 
                            unclaimed_capabilities list
    */ 
    public entry fun remove_account(
        admin: &signer,
        common_account: address,
        claimer: address,
    ) acquires State, Management {
        assert!(account::exists_at(common_account), ECodeForAllErrors);

        assert!(exists<CommonAccount>(common_account), ECodeForAllErrors);
        assert!(exists<Management>(common_account), ECodeForAllErrors);

        let management = borrow_global_mut<Management>(common_account);
        assert! ((management.admin == address_of(admin)) && vector::contains(&management.unclaimed_capabilities, &claimer), ECodeForAllErrors);
        vector::remove_value(&mut management.unclaimed_capabilities, &claimer);
        let state = borrow_global_mut<State>(account::create_resource_address(&@overmind, SEED));
        emit_event(&mut state.remove_account_from_manangement_events, RemoveAccountFromManagementEvent {
            common_account,
            removed_account: claimer
        })
    }

    /* 
		Claim the capability of a common account. Removes the claimer's address from common 
        account's list of unclaimed_capabilities and moves a new Capability resource to the claimer.
        Abort if the common account doesn't exist, isn't initialized with a CommonAccount and 
        Management resource, or the claimer is not in the list, or the claimer already has a 
        capability.
		@param claimer - signer representing one of the common account's claimers
		@param common_account - the address of the common account to acquire the capability for
    */ 
    public entry fun claim_capability(
        claimer: &signer,
        common_account: address,
    ) acquires State, Management {
        assert!(account::exists_at(common_account), ECodeForAllErrors);
        assert!(exists<CommonAccount>(common_account), ECodeForAllErrors);
        assert!(exists<Management>(common_account), ECodeForAllErrors);
        assert!(!exists<Capability>(address_of(claimer)), ECodeForAllErrors);

        let management = borrow_global_mut<Management>(common_account);

        assert!(vector::contains(&management.unclaimed_capabilities, &signer::address_of(claimer)), ECodeForAllErrors);

        vector::remove_value(&mut management.unclaimed_capabilities, &signer::address_of(claimer));
        let cap = Capability {
            common_account
        };

        move_to(claimer, cap);

        let state = borrow_global_mut<State>(account::create_resource_address(&@overmind, SEED));
        emit_event(&mut state.claim_capability_events, ClaimCapabilityEvent {
            common_account,
            claimer: signer::address_of(claimer)
        });

        
    }

    /* 
		Acquire the signer of a common account with a capability. Moves a Capability resource from
        the acquirer to this module (to be dropped) and returns the signer of the associated 
        common account. Abort if the common account doesn't exist, isn't initialized with a 
        CommonAccount and Management resource, the acquirer doesn't have a capability, or the 
        capability isn't for the specified common account.
		@param acquirer - signer representing one of the common account's claimers who has claimed 
                            a Capability
		@param common_account - the address of the common account to acquire the signer for
    */
    public fun acquire_signer(
        acquirer: &signer,
        common_account: address,
    ): signer acquires State, Capability, CommonAccount {
        assert!(account::exists_at(common_account), ECodeForAllErrors);
        assert!(exists<CommonAccount>(common_account), ECodeForAllErrors);
        assert!(exists<Management>(common_account), ECodeForAllErrors);
        assert!(exists<Capability>(address_of(acquirer)), ECodeForAllErrors);

        let state = borrow_global_mut<State>(account::create_resource_address(&@overmind, SEED));
        let account = borrow_global_mut<CommonAccount>(common_account);
        let cap = borrow_global_mut<Capability>(address_of(acquirer));
        assert!(cap.common_account == common_account, ECodeForAllErrors);
        move_from<Capability>(address_of(acquirer));

        emit_event(&mut state.acquire_signer_events, AcquireSignerEvent {
            common_account,
            acquirer: signer::address_of(acquirer)
        });
        create_signer_with_capability(&account.signer_cap)
    }

    //==============================================================================================
    // Helper functions
    //==============================================================================================
    
    //==============================================================================================
    // Validation functions
    //==============================================================================================

    //==============================================================================================
    // Tests - DO NOT MODIFY
    //==============================================================================================
    
    #[test(admin = @overmind, user = @0xA)]
    fun test_init_module_success(
        admin: &signer
    ) acquires State {

        let admin_address = signer::address_of(admin);
        account::create_account_for_test(admin_address);

        init_module(admin);

        let expected_resource_account_address = 
            account::create_resource_address(&admin_address, b"common accounts");
        assert!(account::exists_at(expected_resource_account_address), 0);

        let state = borrow_global<State>(expected_resource_account_address);
        assert!(
            account::get_signer_capability_address(&state.signer_cap) == 
                expected_resource_account_address, 
            0
        );
        
        assert!(event::counter(&state.create_common_account_events) == 0, 2);
        assert!(event::counter(&state.add_account_to_management_events) == 0, 2);
        assert!(event::counter(&state.remove_account_from_manangement_events) == 0, 2);
        assert!(event::counter(&state.claim_capability_events) == 0, 2);
        assert!(event::counter(&state.acquire_signer_events) == 0, 2);
    }

    #[test(admin = @overmind, user = @0xA)]
    fun test_create_common_account_success(
        admin: &signer,
        user: &signer
    ) acquires State, Management, CommonAccount {

        let admin_address = signer::address_of(admin);
        let user_address = signer::address_of(user);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_address);

        init_module(admin);

        create_common_account(user, b"seed 1");

        let expected_common_account_address = 
            account::create_resource_address(&user_address, b"seed 1");
        assert!(account::exists_at(expected_common_account_address), 0);

        let management = borrow_global<Management>(expected_common_account_address);
        assert!(
            management.admin == user_address, 
            0
        );
        assert!(
            vector::length<address>(&management.unclaimed_capabilities) == 0, 
            0
        );

        let common_account = borrow_global<CommonAccount>(expected_common_account_address);
        assert!(
            account::get_signer_capability_address(&common_account.signer_cap) == 
                expected_common_account_address, 
            0
        );
        
        let resource_account_address = 
            account::create_resource_address(&admin_address, b"common accounts");
        let state = borrow_global<State>(resource_account_address);
        assert!(event::counter(&state.create_common_account_events) == 1, 2);
        assert!(event::counter(&state.add_account_to_management_events) == 0, 2);
        assert!(event::counter(&state.remove_account_from_manangement_events) == 0, 2);
        assert!(event::counter(&state.claim_capability_events) == 0, 2);
        assert!(event::counter(&state.acquire_signer_events) == 0, 2);
    }

    #[test(admin = @overmind, user = @0xA)]
    fun test_create_common_account_success_multiple_accounts_for_one_person(
        admin: &signer,
        user: &signer
    ) acquires State, Management, CommonAccount {

        let admin_address = signer::address_of(admin);
        let user_address = signer::address_of(user);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_address);

        init_module(admin);

        create_common_account(user, b"seed 1");
        create_common_account(user, b"seed 2");

        let expected_common_account_address_1 = 
            account::create_resource_address(&user_address, b"seed 1");
        assert!(account::exists_at(expected_common_account_address_1), 0);

        let management_1 = borrow_global<Management>(expected_common_account_address_1);
        assert!(
            management_1.admin == user_address, 
            0
        );
        assert!(
            vector::length<address>(&management_1.unclaimed_capabilities) == 0, 
            0
        );

        let common_account_1 = borrow_global<CommonAccount>(expected_common_account_address_1);
        assert!(
            account::get_signer_capability_address(&common_account_1.signer_cap) == 
                expected_common_account_address_1, 
            0
        );

        let expected_common_account_address_2 = 
            account::create_resource_address(&user_address, b"seed 2");
        assert!(account::exists_at(expected_common_account_address_2), 0);

        let management_2 = borrow_global<Management>(expected_common_account_address_2);
        assert!(
            management_2.admin == user_address, 
            0
        );
        assert!(
            vector::length<address>(&management_2.unclaimed_capabilities) == 0, 
            0
        );

        let common_account_2 = borrow_global<CommonAccount>(expected_common_account_address_2);
        assert!(
            account::get_signer_capability_address(&common_account_2.signer_cap) == 
                expected_common_account_address_2, 
            0
        );
        
        let resource_account_address = 
            account::create_resource_address(&admin_address, b"common accounts");
        let state = borrow_global<State>(resource_account_address);
        assert!(event::counter(&state.create_common_account_events) == 2, 2);
        assert!(event::counter(&state.add_account_to_management_events) == 0, 2);
        assert!(event::counter(&state.remove_account_from_manangement_events) == 0, 2);
        assert!(event::counter(&state.claim_capability_events) == 0, 2);
        assert!(event::counter(&state.acquire_signer_events) == 0, 2);
    }

    #[test(admin = @overmind, user_1 = @0xA, user_2 = @0xB)]
    fun test_create_common_account_success_multiple_accounts_for_multiple_people(
        admin: &signer,
        user_1: &signer,
        user_2: &signer
    ) acquires State, Management, CommonAccount {

        let admin_address = signer::address_of(admin);
        let user_1_address = signer::address_of(user_1);
        let user_2_address = signer::address_of(user_2);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_1_address);
        account::create_account_for_test(user_2_address);

        init_module(admin);

        create_common_account(user_1, b"seed 1");
        create_common_account(user_2, b"seed 1");

        let expected_common_account_address_1 = 
            account::create_resource_address(&user_1_address, b"seed 1");
        assert!(account::exists_at(expected_common_account_address_1), 0);

        let management_1 = borrow_global<Management>(expected_common_account_address_1);
        assert!(
            management_1.admin == user_1_address, 
            0
        );
        assert!(
            vector::length<address>(&management_1.unclaimed_capabilities) == 0, 
            0
        );

        let common_account_1 = borrow_global<CommonAccount>(expected_common_account_address_1);
        assert!(
            account::get_signer_capability_address(&common_account_1.signer_cap) == 
                expected_common_account_address_1, 
            0
        );

        let expected_common_account_address_2 = 
            account::create_resource_address(&user_2_address, b"seed 1");
        assert!(account::exists_at(expected_common_account_address_2), 0);

        let management_2 = borrow_global<Management>(expected_common_account_address_2);
        assert!(
            management_2.admin == user_2_address, 
            0
        );
        assert!(
            vector::length<address>(&management_2.unclaimed_capabilities) == 0, 
            0
        );

        let common_account_2 = borrow_global<CommonAccount>(expected_common_account_address_2);
        assert!(
            account::get_signer_capability_address(&common_account_2.signer_cap) == 
                expected_common_account_address_2, 
            0
        );
        
        let resource_account_address = 
            account::create_resource_address(&admin_address, b"common accounts");
        let state = borrow_global<State>(resource_account_address);
        assert!(event::counter(&state.create_common_account_events) == 2, 2);
        assert!(event::counter(&state.add_account_to_management_events) == 0, 2);
        assert!(event::counter(&state.remove_account_from_manangement_events) == 0, 2);
        assert!(event::counter(&state.claim_capability_events) == 0, 2);
        assert!(event::counter(&state.acquire_signer_events) == 0, 2);
    }

    #[test(admin = @overmind, user = @0xA)]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_create_common_account_failure_account_already_exists(
        admin: &signer,
        user: &signer
    ) acquires State, Management, CommonAccount {

        let admin_address = signer::address_of(admin);
        let user_address = signer::address_of(user);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_address);

        init_module(admin);
        create_common_account(user, b"seed 1");
        create_common_account(user, b"seed 1");

        let expected_common_account_address = 
            account::create_resource_address(&user_address, b"seed 1");
        assert!(account::exists_at(expected_common_account_address), 0);

        let management = borrow_global<Management>(expected_common_account_address);
        assert!(
            management.admin == user_address, 
            0
        );
        assert!(
            vector::length<address>(&management.unclaimed_capabilities) == 0, 
            0
        );

        let common_account = borrow_global<CommonAccount>(expected_common_account_address);
        assert!(
            account::get_signer_capability_address(&common_account.signer_cap) == 
                expected_common_account_address, 
            0
        );
    }

    #[test(admin = @overmind, user_1 = @0xA, user_2 = @0xB)]
    fun test_add_account_success_add_one_account(
        admin: &signer,
        user_1: &signer,
        user_2: &signer
    ) acquires State, Management {

        let admin_address = signer::address_of(admin);
        let user_1_address = signer::address_of(user_1);
        let user_2_address = signer::address_of(user_2);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_1_address);
        account::create_account_for_test(user_2_address);

        init_module(admin);

        create_common_account(user_1, b"seed 1");

        let expected_common_account_address_1 = 
            account::create_resource_address(&user_1_address, b"seed 1");
        assert!(account::exists_at(expected_common_account_address_1), 0);

        add_account(user_1, expected_common_account_address_1, user_2_address);

        let management_1 = borrow_global<Management>(expected_common_account_address_1);
        assert!(
            vector::length<address>(&management_1.unclaimed_capabilities) == 1, 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 0) == &user_2_address, 
            0
        );
        
        let resource_account_address = 
            account::create_resource_address(&admin_address, b"common accounts");
        let state = borrow_global<State>(resource_account_address);
        assert!(event::counter(&state.create_common_account_events) == 1, 2);
        assert!(event::counter(&state.add_account_to_management_events) == 1, 2);
        assert!(event::counter(&state.remove_account_from_manangement_events) == 0, 2);
        assert!(event::counter(&state.claim_capability_events) == 0, 2);
        assert!(event::counter(&state.acquire_signer_events) == 0, 2);
    }

    #[test(admin = @overmind, user_1 = @0xA, user_2 = @0xB)]
    fun test_add_account_success_add_admin(
        admin: &signer,
        user_1: &signer,
        user_2: &signer
    ) acquires State, Management {

        let admin_address = signer::address_of(admin);
        let user_1_address = signer::address_of(user_1);
        let user_2_address = signer::address_of(user_2);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_1_address);
        account::create_account_for_test(user_2_address);

        init_module(admin);

        create_common_account(user_1, b"seed 1");

        let expected_common_account_address_1 = 
            account::create_resource_address(&user_1_address, b"seed 1");
        assert!(account::exists_at(expected_common_account_address_1), 0);

        add_account(user_1, expected_common_account_address_1, user_1_address);

        let management_1 = borrow_global<Management>(expected_common_account_address_1);
        assert!(
            vector::length<address>(&management_1.unclaimed_capabilities) == 1, 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 0) == &user_1_address, 
            0
        );
        
        let resource_account_address = 
            account::create_resource_address(&admin_address, b"common accounts");
        let state = borrow_global<State>(resource_account_address);
        assert!(event::counter(&state.create_common_account_events) == 1, 2);
        assert!(event::counter(&state.add_account_to_management_events) == 1, 2);
        assert!(event::counter(&state.remove_account_from_manangement_events) == 0, 2);
        assert!(event::counter(&state.claim_capability_events) == 0, 2);
        assert!(event::counter(&state.acquire_signer_events) == 0, 2);
    }

    #[test(admin = @overmind, user_1 = @0xA, user_2 = @0xB)]
    fun test_add_account_success_add_multiple_people(
        admin: &signer,
        user_1: &signer,
        user_2: &signer
    ) acquires State, Management {

        let admin_address = signer::address_of(admin);
        let user_1_address = signer::address_of(user_1);
        let user_2_address = signer::address_of(user_2);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_1_address);
        account::create_account_for_test(user_2_address);

        init_module(admin);

        create_common_account(user_1, b"seed 1");

        let expected_common_account_address_1 = 
            account::create_resource_address(&user_1_address, b"seed 1");
        assert!(account::exists_at(expected_common_account_address_1), 0);

        add_account(user_1, expected_common_account_address_1, user_1_address);
        add_account(user_1, expected_common_account_address_1, user_2_address);

        let management_1 = borrow_global<Management>(expected_common_account_address_1);
        assert!(
            vector::length<address>(&management_1.unclaimed_capabilities) == 2, 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 0) == &user_1_address, 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 1) == &user_2_address, 
            0
        );
        
        let resource_account_address = 
            account::create_resource_address(&admin_address, b"common accounts");
        let state = borrow_global<State>(resource_account_address);
        assert!(event::counter(&state.create_common_account_events) == 1, 2);
        assert!(event::counter(&state.add_account_to_management_events) == 2, 2);
        assert!(event::counter(&state.remove_account_from_manangement_events) == 0, 2);
        assert!(event::counter(&state.claim_capability_events) == 0, 2);
        assert!(event::counter(&state.acquire_signer_events) == 0, 2);
    }

    #[test(admin = @overmind, user_1 = @0xA, user_2 = @0xB, user_3 = @0xC)]
    fun test_add_account_success_add_multiple_people_2(
        admin: &signer,
        user_1: &signer,
        user_2: &signer,
        user_3: &signer
    ) acquires State, Management {

        let admin_address = signer::address_of(admin);
        let user_1_address = signer::address_of(user_1);
        let user_2_address = signer::address_of(user_2);
        let user_3_address = signer::address_of(user_3);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_1_address);
        account::create_account_for_test(user_2_address);
        account::create_account_for_test(user_3_address);

        init_module(admin);

        create_common_account(user_1, b"seed 1");

        let expected_common_account_address_1 = 
            account::create_resource_address(&user_1_address, b"seed 1");
        assert!(account::exists_at(expected_common_account_address_1), 0);

        add_account(user_1, expected_common_account_address_1, user_1_address);
        add_account(user_1, expected_common_account_address_1, user_3_address);
        add_account(user_1, expected_common_account_address_1, user_2_address);

        let management_1 = borrow_global<Management>(expected_common_account_address_1);
        assert!(
            vector::length<address>(&management_1.unclaimed_capabilities) ==3 , 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 0) == &user_1_address, 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 1) == &user_3_address, 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 2) == &user_2_address, 
            0
        );
        
        let resource_account_address = 
            account::create_resource_address(&admin_address, b"common accounts");
        let state = borrow_global<State>(resource_account_address);
        assert!(event::counter(&state.create_common_account_events) == 1, 2);
        assert!(event::counter(&state.add_account_to_management_events) == 3, 2);
        assert!(event::counter(&state.remove_account_from_manangement_events) == 0, 2);
        assert!(event::counter(&state.claim_capability_events) == 0, 2);
        assert!(event::counter(&state.acquire_signer_events) == 0, 2);
    }

    #[test(admin = @overmind, user_1 = @0xA, user_2 = @0xB)]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_add_account_failure_common_account_does_not_exist(
        admin: &signer,
        user_1: &signer,
        user_2: &signer
    ) acquires State, Management {

        let admin_address = signer::address_of(admin);
        let user_1_address = signer::address_of(user_1);
        let user_2_address = signer::address_of(user_2);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_1_address);
        account::create_account_for_test(user_2_address);

        init_module(admin);

        let expected_common_account_address_1 = 
            account::create_resource_address(&user_1_address, b"seed 1");

        add_account(user_1, expected_common_account_address_1, user_2_address);

        let management_1 = borrow_global<Management>(expected_common_account_address_1);
        assert!(
            vector::length<address>(&management_1.unclaimed_capabilities) == 1, 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 0) == &user_2_address, 
            0
        );
    }

    #[test(admin = @overmind, user_1 = @0xA, user_2 = @0xB)]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_add_account_failure_common_account_is_not_initialized(
        admin: &signer,
        user_1: &signer,
        user_2: &signer
    ) acquires State, Management {

        let admin_address = signer::address_of(admin);
        let user_1_address = signer::address_of(user_1);
        let user_2_address = signer::address_of(user_2);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_1_address);
        account::create_account_for_test(user_2_address);

        init_module(admin);

        let expected_common_account_address_1 = 
            account::create_resource_address(&user_1_address, b"seed 1");

        add_account(user_1, admin_address, user_2_address);

        let management_1 = borrow_global<Management>(expected_common_account_address_1);
        assert!(
            vector::length<address>(&management_1.unclaimed_capabilities) == 1, 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 0) == &user_2_address, 
            0
        );
    }

    #[test(admin = @overmind, user_1 = @0xA, user_2 = @0xB)]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_add_account_failure_not_admin(
        admin: &signer,
        user_1: &signer,
        user_2: &signer
    ) acquires State, Management {

        let admin_address = signer::address_of(admin);
        let user_1_address = signer::address_of(user_1);
        let user_2_address = signer::address_of(user_2);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_1_address);
        account::create_account_for_test(user_2_address);

        init_module(admin);

        create_common_account(user_1, b"seed 1");

        let expected_common_account_address_1 = 
            account::create_resource_address(&user_1_address, b"seed 1");
        assert!(account::exists_at(expected_common_account_address_1), 0);

        add_account(admin, expected_common_account_address_1, user_2_address);

        let management_1 = borrow_global<Management>(expected_common_account_address_1);
        assert!(
            vector::length<address>(&management_1.unclaimed_capabilities) == 1, 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 0) == &user_2_address, 
            0
        );
    }

    #[test(admin = @overmind, user_1 = @0xA, user_2 = @0xB)]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_add_account_failure_add_existing_claimer(
        admin: &signer,
        user_1: &signer,
        user_2: &signer
    ) acquires State, Management {

        let admin_address = signer::address_of(admin);
        let user_1_address = signer::address_of(user_1);
        let user_2_address = signer::address_of(user_2);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_1_address);
        account::create_account_for_test(user_2_address);

        init_module(admin);

        create_common_account(user_1, b"seed 1");

        let expected_common_account_address_1 = 
            account::create_resource_address(&user_1_address, b"seed 1");
        assert!(account::exists_at(expected_common_account_address_1), 0);

        add_account(user_1, expected_common_account_address_1, user_2_address);
        add_account(user_1, expected_common_account_address_1, user_2_address);

        let management_1 = borrow_global<Management>(expected_common_account_address_1);
        // print(&b"++++++++++++++++++++++++");
        // print(&vector::length<address>(&management_1.unclaimed_capabilities));
        assert!(
            vector::length<address>(&management_1.unclaimed_capabilities) == 1, 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 0) == &user_2_address, 
            0
        );
    }
    
    #[test(admin = @overmind, user_1 = @0xA, user_2 = @0xB, user_3 = @0xC)]
    fun test_remove_account_success_removed_one_claimer(
        admin: &signer,
        user_1: &signer,
        user_2: &signer,
        user_3: &signer
    ) acquires State, Management {

        let admin_address = signer::address_of(admin);
        let user_1_address = signer::address_of(user_1);
        let user_2_address = signer::address_of(user_2);
        let user_3_address = signer::address_of(user_3);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_1_address);
        account::create_account_for_test(user_2_address);
        account::create_account_for_test(user_3_address);

        init_module(admin);

        create_common_account(user_1, b"seed 1");

        let expected_common_account_address_1 = 
            account::create_resource_address(&user_1_address, b"seed 1");
        assert!(account::exists_at(expected_common_account_address_1), 0);

        add_account(user_1, expected_common_account_address_1, user_1_address);
        add_account(user_1, expected_common_account_address_1, user_3_address);
        add_account(user_1, expected_common_account_address_1, user_2_address);

        remove_account(user_1, expected_common_account_address_1, user_1_address);

        let management_1 = borrow_global<Management>(expected_common_account_address_1);
        assert!(
            vector::length<address>(&management_1.unclaimed_capabilities) == 2, 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 0) == &user_3_address, 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 1) == &user_2_address, 
            0
        );
        
        let resource_account_address = 
            account::create_resource_address(&admin_address, b"common accounts");
        let state = borrow_global<State>(resource_account_address);
        assert!(event::counter(&state.create_common_account_events) == 1, 2);
        print(&event::counter(&state.add_account_to_management_events));
        assert!(event::counter(&state.add_account_to_management_events) == 3, 2);
        assert!(event::counter(&state.remove_account_from_manangement_events) == 1, 2);
        assert!(event::counter(&state.claim_capability_events) == 0, 2);
        assert!(event::counter(&state.acquire_signer_events) == 0, 2);
    }

    #[test(admin = @overmind, user_1 = @0xA, user_2 = @0xB, user_3 = @0xC)]
    fun test_remove_account_success_removed_two_claimers(
        admin: &signer,
        user_1: &signer,
        user_2: &signer,
        user_3: &signer
    ) acquires State, Management {

        let admin_address = signer::address_of(admin);
        let user_1_address = signer::address_of(user_1);
        let user_2_address = signer::address_of(user_2);
        let user_3_address = signer::address_of(user_3);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_1_address);
        account::create_account_for_test(user_2_address);
        account::create_account_for_test(user_3_address);

        init_module(admin);

        create_common_account(user_1, b"seed 1");

        let expected_common_account_address_1 = 
            account::create_resource_address(&user_1_address, b"seed 1");
        assert!(account::exists_at(expected_common_account_address_1), 0);

        add_account(user_1, expected_common_account_address_1, user_1_address);
        add_account(user_1, expected_common_account_address_1, user_3_address);
        add_account(user_1, expected_common_account_address_1, user_2_address);

        remove_account(user_1, expected_common_account_address_1, user_1_address);
        remove_account(user_1, expected_common_account_address_1, user_2_address);

        let management_1 = borrow_global<Management>(expected_common_account_address_1);
        assert!(
            vector::length<address>(&management_1.unclaimed_capabilities) == 1, 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 0) == &user_3_address, 
            0
        );
        
        let resource_account_address = 
            account::create_resource_address(&admin_address, b"common accounts");
        let state = borrow_global<State>(resource_account_address);
        assert!(event::counter(&state.create_common_account_events) == 1, 2);
        assert!(event::counter(&state.add_account_to_management_events) == 3, 2);
        assert!(event::counter(&state.remove_account_from_manangement_events) == 2, 2);
        assert!(event::counter(&state.claim_capability_events) == 0, 2);
        assert!(event::counter(&state.acquire_signer_events) == 0, 2);
    }

    #[test(admin = @overmind, user_1 = @0xA, user_2 = @0xB, user_3 = @0xC)]
    fun test_remove_account_success_removed_three_claimers(
        admin: &signer,
        user_1: &signer,
        user_2: &signer,
        user_3: &signer
    ) acquires State, Management {

        let admin_address = signer::address_of(admin);
        let user_1_address = signer::address_of(user_1);
        let user_2_address = signer::address_of(user_2);
        let user_3_address = signer::address_of(user_3);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_1_address);
        account::create_account_for_test(user_2_address);
        account::create_account_for_test(user_3_address);

        init_module(admin);

        create_common_account(user_1, b"seed 1");

        let expected_common_account_address_1 = 
            account::create_resource_address(&user_1_address, b"seed 1");
        assert!(account::exists_at(expected_common_account_address_1), 0);

        add_account(user_1, expected_common_account_address_1, user_1_address);
        add_account(user_1, expected_common_account_address_1, user_3_address);
        add_account(user_1, expected_common_account_address_1, user_2_address);

        remove_account(user_1, expected_common_account_address_1, user_1_address);
        remove_account(user_1, expected_common_account_address_1, user_2_address);
        remove_account(user_1, expected_common_account_address_1, user_3_address);

        let management_1 = borrow_global<Management>(expected_common_account_address_1);
        assert!(
            vector::length<address>(&management_1.unclaimed_capabilities) == 0, 
            0
        );

        let resource_account_address = 
            account::create_resource_address(&admin_address, b"common accounts");
        let state = borrow_global<State>(resource_account_address);
        assert!(event::counter(&state.create_common_account_events) == 1, 2);
        assert!(event::counter(&state.add_account_to_management_events) == 3, 2);
        assert!(event::counter(&state.remove_account_from_manangement_events) == 3, 2);
        assert!(event::counter(&state.claim_capability_events) == 0, 2);
        assert!(event::counter(&state.acquire_signer_events) == 0, 2);
    }

    #[test(admin = @overmind, user_1 = @0xA, user_2 = @0xB, user_3 = @0xC)]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_remove_account_failure_common_account_does_not_exist(
        admin: &signer,
        user_1: &signer,
        user_2: &signer,
        user_3: &signer
    ) acquires State, Management {

        let admin_address = signer::address_of(admin);
        let user_1_address = signer::address_of(user_1);
        let user_2_address = signer::address_of(user_2);
        let user_3_address = signer::address_of(user_3);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_1_address);
        account::create_account_for_test(user_2_address);
        account::create_account_for_test(user_3_address);

        init_module(admin);

        let expected_common_account_address_1 = 
            account::create_resource_address(&user_1_address, b"seed 1");

        remove_account(user_1, expected_common_account_address_1, user_1_address);

        let management_1 = borrow_global<Management>(expected_common_account_address_1);
        assert!(
            vector::length<address>(&management_1.unclaimed_capabilities) == 2, 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 0) == &user_3_address, 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 1) == &user_2_address, 
            0
        );
    }

    #[test(admin = @overmind, user_1 = @0xA, user_2 = @0xB, user_3 = @0xC)]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_remove_account_failure_common_account_is_not_intialized(
        admin: &signer,
        user_1: &signer,
        user_2: &signer,
        user_3: &signer
    ) acquires State, Management {

        let admin_address = signer::address_of(admin);
        let user_1_address = signer::address_of(user_1);
        let user_2_address = signer::address_of(user_2);
        let user_3_address = signer::address_of(user_3);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_1_address);
        account::create_account_for_test(user_2_address);
        account::create_account_for_test(user_3_address);

        init_module(admin);

        create_common_account(user_1, b"seed 1");

        let expected_common_account_address_1 = 
            account::create_resource_address(&user_1_address, b"seed 1");
        assert!(account::exists_at(expected_common_account_address_1), 0);

        add_account(user_1, expected_common_account_address_1, user_1_address);
        add_account(user_1, expected_common_account_address_1, user_3_address);
        add_account(user_1, expected_common_account_address_1, user_2_address);

        remove_account(user_1, admin_address, user_1_address);

        let management_1 = borrow_global<Management>(expected_common_account_address_1);
        assert!(
            vector::length<address>(&management_1.unclaimed_capabilities) == 2, 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 0) == &user_3_address, 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 1) == &user_2_address, 
            0
        );
    }

    #[test(admin = @overmind, user_1 = @0xA, user_2 = @0xB, user_3 = @0xC)]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_remove_account_failure_removed_non_claimer(
        admin: &signer,
        user_1: &signer,
        user_2: &signer,
        user_3: &signer
    ) acquires State, Management {

        let admin_address = signer::address_of(admin);
        let user_1_address = signer::address_of(user_1);
        let user_2_address = signer::address_of(user_2);
        let user_3_address = signer::address_of(user_3);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_1_address);
        account::create_account_for_test(user_2_address);
        account::create_account_for_test(user_3_address);

        init_module(admin);

        create_common_account(user_1, b"seed 1");

        let expected_common_account_address_1 = 
            account::create_resource_address(&user_1_address, b"seed 1");
        assert!(account::exists_at(expected_common_account_address_1), 0);

        add_account(user_1, expected_common_account_address_1, user_1_address);
        add_account(user_1, expected_common_account_address_1, user_3_address);
        add_account(user_1, expected_common_account_address_1, user_2_address);

        remove_account(user_1, expected_common_account_address_1, user_1_address);
        remove_account(user_1, expected_common_account_address_1, user_2_address);
        remove_account(user_1, expected_common_account_address_1, user_3_address);
        remove_account(user_1, expected_common_account_address_1, user_1_address);

        let management_1 = borrow_global<Management>(expected_common_account_address_1);
        assert!(
            vector::length<address>(&management_1.unclaimed_capabilities) == 0, 
            0
        );
    }

    #[test(admin = @overmind, user_1 = @0xA, user_2 = @0xB, user_3 = @0xC)]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_remove_account_failure_non_admin(
        admin: &signer,
        user_1: &signer,
        user_2: &signer,
        user_3: &signer
    ) acquires State, Management {

        let admin_address = signer::address_of(admin);
        let user_1_address = signer::address_of(user_1);
        let user_2_address = signer::address_of(user_2);
        let user_3_address = signer::address_of(user_3);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_1_address);
        account::create_account_for_test(user_2_address);
        account::create_account_for_test(user_3_address);

        init_module(admin);

        create_common_account(user_1, b"seed 1");

        let expected_common_account_address_1 = 
            account::create_resource_address(&user_1_address, b"seed 1");
        assert!(account::exists_at(expected_common_account_address_1), 0);

        add_account(user_1, expected_common_account_address_1, user_1_address);
        add_account(user_1, expected_common_account_address_1, user_3_address);
        add_account(user_1, expected_common_account_address_1, user_2_address);

        remove_account(admin, expected_common_account_address_1, user_1_address);
        remove_account(user_1, expected_common_account_address_1, user_2_address);
        remove_account(user_1, expected_common_account_address_1, user_3_address);
        remove_account(user_1, expected_common_account_address_1, user_1_address);

        let management_1 = borrow_global<Management>(expected_common_account_address_1);
        assert!(
            vector::length<address>(&management_1.unclaimed_capabilities) == 0, 
            0
        );
    }

    #[test(admin = @overmind, user_1 = @0xA, user_2 = @0xB, user_3 = @0xC)]
    fun test_claim_capability_success_one_claim(
        admin: &signer,
        user_1: &signer,
        user_2: &signer,
        user_3: &signer
    ) acquires State, Management, Capability {

        let admin_address = signer::address_of(admin);
        let user_1_address = signer::address_of(user_1);
        let user_2_address = signer::address_of(user_2);
        let user_3_address = signer::address_of(user_3);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_1_address);
        account::create_account_for_test(user_2_address);
        account::create_account_for_test(user_3_address);

        init_module(admin);

        create_common_account(user_1, b"seed 1");

        let expected_common_account_address_1 = 
            account::create_resource_address(&user_1_address, b"seed 1");
        assert!(account::exists_at(expected_common_account_address_1), 0);

        add_account(user_1, expected_common_account_address_1, user_1_address);
        add_account(user_1, expected_common_account_address_1, user_3_address);
        add_account(user_1, expected_common_account_address_1, user_2_address);

        claim_capability(user_3, expected_common_account_address_1);

        let management_1 = borrow_global<Management>(expected_common_account_address_1);
        assert!(
            vector::length<address>(&management_1.unclaimed_capabilities) == 2, 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 0) == &user_1_address, 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 1) == &user_2_address, 
            0
        );

        assert!(
            exists<Capability>(user_1_address) == false, 
            0
        );
        assert!(
            exists<Capability>(user_2_address) == false, 
            0
        );
        assert!(
            exists<Capability>(user_3_address) == true, 
            0
        );
        let capability = borrow_global<Capability>(user_3_address);
        assert!(
            capability.common_account == expected_common_account_address_1, 
            0
        );
        
        let resource_account_address = 
            account::create_resource_address(&admin_address, b"common accounts");
        let state = borrow_global<State>(resource_account_address);
        assert!(event::counter(&state.create_common_account_events) == 1, 2);
        assert!(event::counter(&state.add_account_to_management_events) == 3, 2);
        assert!(event::counter(&state.remove_account_from_manangement_events) == 0, 2);
        assert!(event::counter(&state.claim_capability_events) == 1, 2);
        assert!(event::counter(&state.acquire_signer_events) == 0, 2);
    }

    #[test(admin = @overmind, user_1 = @0xA, user_2 = @0xB, user_3 = @0xC)]
    fun test_claim_capability_success_multiple_claims(
        admin: &signer,
        user_1: &signer,
        user_2: &signer,
        user_3: &signer
    ) acquires State, Management, Capability {

        let admin_address = signer::address_of(admin);
        let user_1_address = signer::address_of(user_1);
        let user_2_address = signer::address_of(user_2);
        let user_3_address = signer::address_of(user_3);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_1_address);
        account::create_account_for_test(user_2_address);
        account::create_account_for_test(user_3_address);

        init_module(admin);

        create_common_account(user_1, b"seed 1");

        let expected_common_account_address_1 = 
            account::create_resource_address(&user_1_address, b"seed 1");
        assert!(account::exists_at(expected_common_account_address_1), 0);

        add_account(user_1, expected_common_account_address_1, user_1_address);
        add_account(user_1, expected_common_account_address_1, user_3_address);
        add_account(user_1, expected_common_account_address_1, user_2_address);

        claim_capability(user_3, expected_common_account_address_1);
        claim_capability(user_1, expected_common_account_address_1);

        let management_1 = borrow_global<Management>(expected_common_account_address_1);
        assert!(
            vector::length<address>(&management_1.unclaimed_capabilities) == 1, 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 0) == &user_2_address, 
            0
        );

        assert!(
            exists<Capability>(user_1_address) == true, 
            0
        );
        assert!(
            exists<Capability>(user_2_address) == false, 
            0
        );
        assert!(
            exists<Capability>(user_3_address) == true, 
            0
        );
        let capability_1 = borrow_global<Capability>(user_1_address);
        assert!(
            capability_1.common_account == expected_common_account_address_1, 
            0
        );
        let capability_3 = borrow_global<Capability>(user_3_address);
        assert!(
            capability_3.common_account == expected_common_account_address_1, 
            0
        );
        
        let resource_account_address = 
            account::create_resource_address(&admin_address, b"common accounts");
        let state = borrow_global<State>(resource_account_address);
        assert!(event::counter(&state.create_common_account_events) == 1, 2);
        assert!(event::counter(&state.add_account_to_management_events) == 3, 2);
        assert!(event::counter(&state.remove_account_from_manangement_events) == 0, 2);
        assert!(event::counter(&state.claim_capability_events) == 2, 2);
        assert!(event::counter(&state.acquire_signer_events) == 0, 2);
    }

    #[test(admin = @overmind, user_1 = @0xA, user_2 = @0xB, user_3 = @0xC)]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_claim_capability_failure_common_account_does_not_exist(
        admin: &signer,
        user_1: &signer,
        user_2: &signer,
        user_3: &signer
    ) acquires State, Management, Capability {

        let admin_address = signer::address_of(admin);
        let user_1_address = signer::address_of(user_1);
        let user_2_address = signer::address_of(user_2);
        let user_3_address = signer::address_of(user_3);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_1_address);
        account::create_account_for_test(user_2_address);
        account::create_account_for_test(user_3_address);

        init_module(admin);

        let expected_common_account_address_1 = 
            account::create_resource_address(&user_1_address, b"seed 1");

        claim_capability(user_3, expected_common_account_address_1);

        let management_1 = borrow_global<Management>(expected_common_account_address_1);
        assert!(
            vector::length<address>(&management_1.unclaimed_capabilities) == 2, 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 0) == &user_1_address, 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 1) == &user_2_address, 
            0
        );

        assert!(
            exists<Capability>(user_1_address) == false, 
            0
        );
        assert!(
            exists<Capability>(user_2_address) == false, 
            0
        );
        assert!(
            exists<Capability>(user_3_address) == true, 
            0
        );
        let capability = borrow_global<Capability>(user_3_address);
        assert!(
            capability.common_account == expected_common_account_address_1, 
            0
        );
    }

    #[test(admin = @overmind, user_1 = @0xA, user_2 = @0xB, user_3 = @0xC)]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_claim_capability_failure_common_account_is_not_initialized(
        admin: &signer,
        user_1: &signer,
        user_2: &signer,
        user_3: &signer
    ) acquires State, Management, Capability {

        let admin_address = signer::address_of(admin);
        let user_1_address = signer::address_of(user_1);
        let user_2_address = signer::address_of(user_2);
        let user_3_address = signer::address_of(user_3);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_1_address);
        account::create_account_for_test(user_2_address);
        account::create_account_for_test(user_3_address);

        init_module(admin);

        create_common_account(user_1, b"seed 1");

        let expected_common_account_address_1 = 
            account::create_resource_address(&user_1_address, b"seed 1");
        assert!(account::exists_at(expected_common_account_address_1), 0);

        add_account(user_1, expected_common_account_address_1, user_1_address);
        add_account(user_1, expected_common_account_address_1, user_3_address);
        add_account(user_1, expected_common_account_address_1, user_2_address);

        claim_capability(user_3, admin_address);

        let management_1 = borrow_global<Management>(expected_common_account_address_1);
        assert!(
            vector::length<address>(&management_1.unclaimed_capabilities) == 2, 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 0) == &user_1_address, 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 1) == &user_2_address, 
            0
        );

        assert!(
            exists<Capability>(user_1_address) == false, 
            0
        );
        assert!(
            exists<Capability>(user_2_address) == false, 
            0
        );
        assert!(
            exists<Capability>(user_3_address) == true, 
            0
        );
        let capability = borrow_global<Capability>(user_3_address);
        assert!(
            capability.common_account == expected_common_account_address_1, 
            0
        );
    }

    #[test(admin = @overmind, user_1 = @0xA, user_2 = @0xB, user_3 = @0xC)]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_claim_capability_failure_not_in_claimer_list(
        admin: &signer,
        user_1: &signer,
        user_2: &signer,
        user_3: &signer
    ) acquires State, Management, Capability {

        let admin_address = signer::address_of(admin);
        let user_1_address = signer::address_of(user_1);
        let user_2_address = signer::address_of(user_2);
        let user_3_address = signer::address_of(user_3);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_1_address);
        account::create_account_for_test(user_2_address);
        account::create_account_for_test(user_3_address);

        init_module(admin);

        create_common_account(user_1, b"seed 1");

        let expected_common_account_address_1 = 
            account::create_resource_address(&user_1_address, b"seed 1");
        assert!(account::exists_at(expected_common_account_address_1), 0);

        add_account(user_1, expected_common_account_address_1, user_1_address);
        add_account(user_1, expected_common_account_address_1, user_2_address);

        claim_capability(user_3, expected_common_account_address_1);

        let management_1 = borrow_global<Management>(expected_common_account_address_1);
        assert!(
            vector::length<address>(&management_1.unclaimed_capabilities) == 2, 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 0) == &user_1_address, 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 1) == &user_2_address, 
            0
        );

        assert!(
            exists<Capability>(user_1_address) == false, 
            0
        );
        assert!(
            exists<Capability>(user_2_address) == false, 
            0
        );
        assert!(
            exists<Capability>(user_3_address) == true, 
            0
        );
        let capability = borrow_global<Capability>(user_3_address);
        assert!(
            capability.common_account == expected_common_account_address_1, 
            0
        );
    }

    #[test(admin = @overmind, user_1 = @0xA, user_2 = @0xB, user_3 = @0xC)]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_claim_capability_failure_user_alread_has_capability(
        admin: &signer,
        user_1: &signer,
        user_2: &signer,
        user_3: &signer
    ) acquires State, Management, Capability {

        let admin_address = signer::address_of(admin);
        let user_1_address = signer::address_of(user_1);
        let user_2_address = signer::address_of(user_2);
        let user_3_address = signer::address_of(user_3);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_1_address);
        account::create_account_for_test(user_2_address);
        account::create_account_for_test(user_3_address);

        init_module(admin);

        create_common_account(user_1, b"seed 1");
        create_common_account(user_1, b"seed 2");

        let expected_common_account_address_1 = 
            account::create_resource_address(&user_1_address, b"seed 1");
        let expected_common_account_address_2 = 
            account::create_resource_address(&user_1_address, b"seed 2");

        add_account(user_1, expected_common_account_address_1, user_1_address);
        add_account(user_1, expected_common_account_address_1, user_2_address);
        add_account(user_1, expected_common_account_address_2, user_1_address);
        add_account(user_1, expected_common_account_address_2, user_2_address);

        claim_capability(user_2, expected_common_account_address_1);
        claim_capability(user_2, expected_common_account_address_2);

        let management_1 = borrow_global<Management>(expected_common_account_address_1);
        assert!(
            vector::length<address>(&management_1.unclaimed_capabilities) == 2, 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 0) == &user_1_address, 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 1) == &user_2_address, 
            0
        );

        assert!(
            exists<Capability>(user_1_address) == false, 
            0
        );
        assert!(
            exists<Capability>(user_2_address) == false, 
            0
        );
        assert!(
            exists<Capability>(user_3_address) == true, 
            0
        );
        let capability = borrow_global<Capability>(user_3_address);
        assert!(
            capability.common_account == expected_common_account_address_1, 
            0
        );
    }


    #[test(admin = @overmind, user_1 = @0xA, user_2 = @0xB, user_3 = @0xC)]
    fun test_acquire_signer_success_acquire_signer_1(
        admin: &signer,
        user_1: &signer,
        user_2: &signer,
        user_3: &signer
    ) acquires State, Management, Capability, CommonAccount {

        let admin_address = signer::address_of(admin);
        let user_1_address = signer::address_of(user_1);
        let user_2_address = signer::address_of(user_2);
        let user_3_address = signer::address_of(user_3);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_1_address);
        account::create_account_for_test(user_2_address);
        account::create_account_for_test(user_3_address);

        init_module(admin);

        create_common_account(user_1, b"seed 1");

        let expected_common_account_address_1 = 
            account::create_resource_address(&user_1_address, b"seed 1");
        assert!(account::exists_at(expected_common_account_address_1), 0);

        add_account(user_1, expected_common_account_address_1, user_1_address);
        add_account(user_1, expected_common_account_address_1, user_3_address);
        add_account(user_1, expected_common_account_address_1, user_2_address);

        claim_capability(user_3, expected_common_account_address_1);
        claim_capability(user_1, expected_common_account_address_1);

        let management_1 = borrow_global<Management>(expected_common_account_address_1);
        assert!(
            vector::length<address>(&management_1.unclaimed_capabilities) == 1, 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 0) == &user_2_address, 
            0
        );

        assert!(
            exists<Capability>(user_1_address) == true, 
            0
        );
        assert!(
            exists<Capability>(user_2_address) == false, 
            0
        );
        assert!(
            exists<Capability>(user_3_address) == true, 
            0
        );
        let capability_1 = borrow_global<Capability>(user_1_address);
        assert!(
            capability_1.common_account == expected_common_account_address_1, 
            0
        );
        let capability_3 = borrow_global<Capability>(user_3_address);
        assert!(
            capability_3.common_account == expected_common_account_address_1, 
            0
        );

        let common_account_signer = acquire_signer(user_1, expected_common_account_address_1);

        assert!(
            signer::address_of(&common_account_signer) == expected_common_account_address_1,
            0
        );

        assert!(
            exists<Capability>(user_1_address) == false, 
            0
        );
        assert!(
            exists<Capability>(user_2_address) == false, 
            0
        );
        assert!(
            exists<Capability>(user_3_address) == true, 
            0
        );
        
        let resource_account_address = 
            account::create_resource_address(&admin_address, b"common accounts");
        let state = borrow_global<State>(resource_account_address);
        assert!(event::counter(&state.create_common_account_events) == 1, 2);
        assert!(event::counter(&state.add_account_to_management_events) == 3, 2);
        assert!(event::counter(&state.remove_account_from_manangement_events) == 0, 2);
        assert!(event::counter(&state.claim_capability_events) == 2, 2);
        assert!(event::counter(&state.acquire_signer_events) == 1, 2);
    }

    #[test(admin = @overmind, user_1 = @0xA, user_2 = @0xB, user_3 = @0xC)]
    fun test_acquire_signer_success_acquire_signer_2(
        admin: &signer,
        user_1: &signer,
        user_2: &signer,
        user_3: &signer
    ) acquires State, Management, Capability, CommonAccount {

        let admin_address = signer::address_of(admin);
        let user_1_address = signer::address_of(user_1);
        let user_2_address = signer::address_of(user_2);
        let user_3_address = signer::address_of(user_3);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_1_address);
        account::create_account_for_test(user_2_address);
        account::create_account_for_test(user_3_address);

        init_module(admin);

        create_common_account(user_1, b"seed 1");

        let expected_common_account_address_1 = 
            account::create_resource_address(&user_1_address, b"seed 1");
        assert!(account::exists_at(expected_common_account_address_1), 0);

        add_account(user_1, expected_common_account_address_1, user_1_address);
        add_account(user_1, expected_common_account_address_1, user_3_address);
        add_account(user_1, expected_common_account_address_1, user_2_address);
        print(&exists<Capability>(address_of(user_3)));

        claim_capability(user_3, expected_common_account_address_1);
        claim_capability(user_1, expected_common_account_address_1);

        let management_1 = borrow_global<Management>(expected_common_account_address_1);
        assert!(
            vector::length<address>(&management_1.unclaimed_capabilities) == 1, 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 0) == &user_2_address, 
            0
        );

        assert!(
            exists<Capability>(user_1_address) == true, 
            0
        );
        assert!(
            exists<Capability>(user_2_address) == false, 
            0
        );
        assert!(
            exists<Capability>(user_3_address) == true, 
            0
        );
        let capability_1 = borrow_global<Capability>(user_1_address);
        assert!(
            capability_1.common_account == expected_common_account_address_1, 
            0
        );
        let capability_3 = borrow_global<Capability>(user_3_address);
        assert!(
            capability_3.common_account == expected_common_account_address_1, 
            0
        );

        let common_account_signer = acquire_signer(user_3, expected_common_account_address_1);

        assert!(
            signer::address_of(&common_account_signer) == expected_common_account_address_1,
            0
        );

        assert!(
            exists<Capability>(user_1_address) == true, 
            0
        );
        assert!(
            exists<Capability>(user_2_address) == false, 
            0
        );
        assert!(
            exists<Capability>(user_3_address) == false, 
            0
        );
        
        let resource_account_address = 
            account::create_resource_address(&admin_address, b"common accounts");
        let state = borrow_global<State>(resource_account_address);
        assert!(event::counter(&state.create_common_account_events) == 1, 2);
        assert!(event::counter(&state.add_account_to_management_events) == 3, 2);
        assert!(event::counter(&state.remove_account_from_manangement_events) == 0, 2);
        assert!(event::counter(&state.claim_capability_events) == 2, 2);
        assert!(event::counter(&state.acquire_signer_events) == 1, 2);
    }

    #[test(admin = @overmind, user_1 = @0xA, user_2 = @0xB, user_3 = @0xC)]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_acquire_signer_failure_common_account_does_not_exist(
        admin: &signer,
        user_1: &signer,
        user_2: &signer,
        user_3: &signer
    ) acquires State, Capability, CommonAccount {

        let admin_address = signer::address_of(admin);
        let user_1_address = signer::address_of(user_1);
        let user_2_address = signer::address_of(user_2);
        let user_3_address = signer::address_of(user_3);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_1_address);
        account::create_account_for_test(user_2_address);
        account::create_account_for_test(user_3_address);

        init_module(admin);

        let expected_common_account_address_1 = 
            account::create_resource_address(&user_1_address, b"seed 1");

        let common_account_signer = acquire_signer(user_1, expected_common_account_address_1);

        assert!(
            signer::address_of(&common_account_signer) == expected_common_account_address_1,
            0
        );
    }

    #[test(admin = @overmind, user_1 = @0xA, user_2 = @0xB, user_3 = @0xC)]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_acquire_signer_failure_common_account_is_not_initialized(
        admin: &signer,
        user_1: &signer,
        user_2: &signer,
        user_3: &signer
    ) acquires State, Management, Capability, CommonAccount {

        let admin_address = signer::address_of(admin);
        let user_1_address = signer::address_of(user_1);
        let user_2_address = signer::address_of(user_2);
        let user_3_address = signer::address_of(user_3);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_1_address);
        account::create_account_for_test(user_2_address);
        account::create_account_for_test(user_3_address);

        init_module(admin);

        create_common_account(user_1, b"seed 1");

        let expected_common_account_address_1 = 
            account::create_resource_address(&user_1_address, b"seed 1");
        assert!(account::exists_at(expected_common_account_address_1), 0);

        add_account(user_1, expected_common_account_address_1, user_1_address);
        add_account(user_1, expected_common_account_address_1, user_3_address);
        add_account(user_1, expected_common_account_address_1, user_2_address);

        claim_capability(user_3, expected_common_account_address_1);
        claim_capability(user_1, expected_common_account_address_1);

        let management_1 = borrow_global<Management>(expected_common_account_address_1);
        assert!(
            vector::length<address>(&management_1.unclaimed_capabilities) == 1, 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 0) == &user_2_address, 
            0
        );

        assert!(
            exists<Capability>(user_1_address) == true, 
            0
        );
        assert!(
            exists<Capability>(user_2_address) == false, 
            0
        );
        assert!(
            exists<Capability>(user_3_address) == true, 
            0
        );
        let capability_1 = borrow_global<Capability>(user_1_address);
        assert!(
            capability_1.common_account == expected_common_account_address_1, 
            0
        );
        let capability_3 = borrow_global<Capability>(user_3_address);
        assert!(
            capability_3.common_account == expected_common_account_address_1, 
            0
        );

        let common_account_signer = acquire_signer(user_1, admin_address);

        assert!(
            signer::address_of(&common_account_signer) == expected_common_account_address_1,
            0
        );
    }

    #[test(admin = @overmind, user_1 = @0xA, user_2 = @0xB, user_3 = @0xC)]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_acquire_signer_failure_no_capability(
        admin: &signer,
        user_1: &signer,
        user_2: &signer,
        user_3: &signer
    ) acquires State, Management, Capability, CommonAccount {

        let admin_address = signer::address_of(admin);
        let user_1_address = signer::address_of(user_1);
        let user_2_address = signer::address_of(user_2);
        let user_3_address = signer::address_of(user_3);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_1_address);
        account::create_account_for_test(user_2_address);
        account::create_account_for_test(user_3_address);

        init_module(admin);

        create_common_account(user_1, b"seed 1");

        let expected_common_account_address_1 = 
            account::create_resource_address(&user_1_address, b"seed 1");
        assert!(account::exists_at(expected_common_account_address_1), 0);

        add_account(user_1, expected_common_account_address_1, user_1_address);
        add_account(user_1, expected_common_account_address_1, user_3_address);
        add_account(user_1, expected_common_account_address_1, user_2_address);

        claim_capability(user_3, expected_common_account_address_1);

        let common_account_signer = acquire_signer(user_1, expected_common_account_address_1);

        assert!(
            signer::address_of(&common_account_signer) == expected_common_account_address_1,
            0
        );
    }

    #[test(admin = @overmind, user_1 = @0xA, user_2 = @0xB, user_3 = @0xC)]
    #[expected_failure(abort_code = ECodeForAllErrors, location = Self)]
    fun test_acquire_signer_failure_capability_for_other_account(
        admin: &signer,
        user_1: &signer,
        user_2: &signer,
        user_3: &signer
    ) acquires State, Management, Capability, CommonAccount {

        let admin_address = signer::address_of(admin);
        let user_1_address = signer::address_of(user_1);
        let user_2_address = signer::address_of(user_2);
        let user_3_address = signer::address_of(user_3);
        account::create_account_for_test(admin_address);
        account::create_account_for_test(user_1_address);
        account::create_account_for_test(user_2_address);
        account::create_account_for_test(user_3_address);

        init_module(admin);

        create_common_account(user_1, b"seed 1");
        create_common_account(user_1, b"seed 2");

        let expected_common_account_address_1 = 
            account::create_resource_address(&user_1_address, b"seed 1");
            let expected_common_account_address_2 = 
            account::create_resource_address(&user_1_address, b"seed 2");
        assert!(account::exists_at(expected_common_account_address_1), 0);

        add_account(user_1, expected_common_account_address_1, user_1_address);
        add_account(user_1, expected_common_account_address_1, user_3_address);
        add_account(user_1, expected_common_account_address_1, user_2_address);

        claim_capability(user_3, expected_common_account_address_1);
        claim_capability(user_1, expected_common_account_address_1);

        let management_1 = borrow_global<Management>(expected_common_account_address_1);
        assert!(
            vector::length<address>(&management_1.unclaimed_capabilities) == 1, 
            0
        );
        assert!(
            vector::borrow<address>(&management_1.unclaimed_capabilities, 0) == &user_2_address, 
            0
        );

        assert!(
            exists<Capability>(user_1_address) == true, 
            0
        );
        assert!(
            exists<Capability>(user_2_address) == false, 
            0
        );
        assert!(
            exists<Capability>(user_3_address) == true, 
            0
        );
        let capability_1 = borrow_global<Capability>(user_1_address);
        assert!(
            capability_1.common_account == expected_common_account_address_1, 
            0
        );
        let capability_3 = borrow_global<Capability>(user_3_address);
        assert!(
            capability_3.common_account == expected_common_account_address_1, 
            0
        );

        let common_account_signer = acquire_signer(user_1, expected_common_account_address_2);

        assert!(
            signer::address_of(&common_account_signer) == expected_common_account_address_1,
            0
        );
    }
}
