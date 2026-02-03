// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";

import {ERC8004Integration, IERC8004IdentityRegistry, IERC8004ReputationRegistry} from "../src/erc8004/ERC8004Integration.sol";
import {SwarmAgentRegistry} from "../src/erc8004/SwarmAgentRegistry.sol";

/// @title ERC8004IntegrationTest
/// @notice Tests for ERC-8004 integration components
contract ERC8004IntegrationTest is Test {
    
    // ============ ERC8004Integration Library Tests ============
    
    function test_sepoliaAddresses() public pure {
        assertEq(
            ERC8004Integration.SEPOLIA_IDENTITY_REGISTRY,
            0x8004A818BFB912233c491871b3d84c89A494BD9e
        );
        assertEq(
            ERC8004Integration.SEPOLIA_REPUTATION_REGISTRY,
            0x8004B663056A597Dffe9eCcC1965A193B7388713
        );
    }
    
    function test_mainnetAddresses() public pure {
        assertEq(
            ERC8004Integration.MAINNET_IDENTITY_REGISTRY,
            0x8004A169FB4a3325136EB29fA0ceB6D2e539a432
        );
        assertEq(
            ERC8004Integration.MAINNET_REPUTATION_REGISTRY,
            0x8004BAa17C55a88189AE136b182e5fdA19dE9b63
        );
    }
    
    function test_normalizeToWad_18decimals() public pure {
        int128 value = 5e18;
        int256 normalized = ERC8004Integration.normalizeToWad(value, 18);
        assertEq(normalized, 5e18);
    }
    
    function test_normalizeToWad_6decimals() public pure {
        int128 value = 5e6;
        int256 normalized = ERC8004Integration.normalizeToWad(value, 6);
        assertEq(normalized, 5e18);
    }
    
    function test_normalizeToWad_20decimals() public pure {
        int128 value = 5e20;
        int256 normalized = ERC8004Integration.normalizeToWad(value, 20);
        assertEq(normalized, 5e18);
    }
    
    function test_normalizeToWad_negative() public pure {
        int128 value = -3e18;
        int256 normalized = ERC8004Integration.normalizeToWad(value, 18);
        assertEq(normalized, -3e18);
    }
    
    function test_calculateReputationWeight_excellent() public pure {
        // +5 reputation = 2x weight (capped at >=5)
        uint256 weight = ERC8004Integration.calculateReputationWeight(5e18);
        assertEq(weight, 2e18);
    }
    
    function test_calculateReputationWeight_good() public pure {
        // +3 reputation = 1.3x weight (1 + 3/10 = 1.3)
        uint256 weight = ERC8004Integration.calculateReputationWeight(3e18);
        assertEq(weight, 1.3e18);
    }
    
    function test_calculateReputationWeight_neutral() public pure {
        // 0 reputation = 1x weight
        uint256 weight = ERC8004Integration.calculateReputationWeight(0);
        assertEq(weight, 1e18);
    }
    
    function test_calculateReputationWeight_poor() public pure {
        // -5 reputation = 0.5x weight
        uint256 weight = ERC8004Integration.calculateReputationWeight(-5e18);
        assertEq(weight, 0.5e18);
    }
    
    function test_calculateReputationWeight_bounds() public pure {
        // Very high reputation should cap at reasonable weight
        uint256 weightHigh = ERC8004Integration.calculateReputationWeight(10e18);
        assertEq(weightHigh, 2e18); // Capped at 2x
        
        // Very low reputation should cap at minimum weight
        uint256 weightLow = ERC8004Integration.calculateReputationWeight(-10e18);
        assertEq(weightLow, 0.5e18); // Capped at 0.5x
    }
    
    function test_getReputationTier() public pure {
        // Excellent: >= 5 WAD
        assertEq(ERC8004Integration.getReputationTier(5e18), 4);
        assertEq(ERC8004Integration.getReputationTier(10e18), 4);
        
        // Good: >= 2 WAD
        assertEq(ERC8004Integration.getReputationTier(2e18), 3);
        assertEq(ERC8004Integration.getReputationTier(4e18), 3);
        
        // Neutral: >= 0 WAD
        assertEq(ERC8004Integration.getReputationTier(0), 2);
        assertEq(ERC8004Integration.getReputationTier(1e18), 2);
        
        // Poor: >= -1 WAD
        assertEq(ERC8004Integration.getReputationTier(-1e18), 1);
        
        // Very Poor: < -1 WAD
        assertEq(ERC8004Integration.getReputationTier(-2e18), 0);
    }
    
    function test_meetsReputationRequirement() public pure {
        assertTrue(ERC8004Integration.meetsReputationRequirement(5e18, 0));
        assertTrue(ERC8004Integration.meetsReputationRequirement(0, -1e18));
        assertFalse(ERC8004Integration.meetsReputationRequirement(-2e18, 0));
    }
    
    function test_tags() public pure {
        assertEq(
            keccak256(bytes(ERC8004Integration.TAG_SWARM_ROUTING)),
            keccak256(bytes("swarm-routing"))
        );
        assertEq(
            keccak256(bytes(ERC8004Integration.TAG_MEV_PROTECTION)),
            keccak256(bytes("mev-protection"))
        );
    }
    
    // ============ SwarmAgentRegistry Tests ============
    
    SwarmAgentRegistry public registry;
    
    function setUp() public {
        // Deploy with mock addresses (won't actually interact with ERC-8004)
        registry = new SwarmAgentRegistry(
            address(0x1), // mock identity registry
            address(0x2)  // mock reputation registry
        );
    }
    
    function test_registry_initialization() public view {
        assertEq(address(registry.identityRegistry()), address(0x1));
        assertEq(address(registry.reputationRegistry()), address(0x2));
    }
    
    function test_registry_setFeedbackClientAuthorization() public {
        address client = address(0x123);
        
        assertFalse(registry.authorizedFeedbackClients(client));
        
        registry.setFeedbackClientAuthorization(client, true);
        assertTrue(registry.authorizedFeedbackClients(client));
        
        registry.setFeedbackClientAuthorization(client, false);
        assertFalse(registry.authorizedFeedbackClients(client));
    }
    
    function test_registry_onlyOwnerCanAuthorize() public {
        address client = address(0x123);
        address notOwner = address(0x456);
        
        vm.prank(notOwner);
        vm.expectRevert();
        registry.setFeedbackClientAuthorization(client, true);
    }
    
    function test_registry_validateAgentType() public {
        // Valid types (would work with real identity registry)
        // Note: We can't test full registration without mocking ERC-8004
        
        // Just verify the registry was deployed correctly
        assertTrue(address(registry) != address(0));
    }
    
    function test_registry_getAllAgents_empty() public view {
        address[] memory agents = registry.getAllAgents();
        assertEq(agents.length, 0);
    }
    
    function test_registry_getActiveAgents_empty() public view {
        address[] memory agents = registry.getActiveAgents();
        assertEq(agents.length, 0);
    }
    
    function test_registry_isAgentActive_unregistered() public view {
        assertFalse(registry.isAgentActive(address(0x123)));
    }
    
    // ============ Fuzz Tests ============
    
    function testFuzz_normalizeToWad(int128 value, uint8 decimals) public pure {
        vm.assume(decimals <= 30); // Reasonable range
        
        int256 normalized = ERC8004Integration.normalizeToWad(value, decimals);
        
        // Value should scale appropriately
        if (decimals == 18) {
            assertEq(normalized, int256(value));
        }
    }
    
    function testFuzz_reputationWeight(int256 reputation) public pure {
        vm.assume(reputation >= -100e18 && reputation <= 100e18);
        
        uint256 weight = ERC8004Integration.calculateReputationWeight(reputation);
        
        // Weight should be bounded
        assertTrue(weight >= 0.5e18);
        assertTrue(weight <= 2e18);
    }
    
    function testFuzz_reputationTier(int256 reputation) public pure {
        vm.assume(reputation >= -100e18 && reputation <= 100e18);
        
        uint8 tier = ERC8004Integration.getReputationTier(reputation);
        
        // Tier should be 0-4
        assertTrue(tier <= 4);
    }
}
