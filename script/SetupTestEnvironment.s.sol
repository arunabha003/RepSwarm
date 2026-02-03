// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PathKey} from "v4-periphery/src/libraries/PathKey.sol";

import {SwarmCoordinator} from "../src/SwarmCoordinator.sol";
import {MevRouterHook} from "../src/hooks/MevRouterHook.sol";
import {OracleRegistry} from "../src/oracles/OracleRegistry.sol";

// Simple ERC20 for testing
contract TestToken {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }
    
    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}

/// @title SetupTestEnvironment
/// @notice Deploys test tokens, creates pools, adds liquidity for full demo
contract SetupTestEnvironment is Script {
    using CurrencyLibrary for Currency;

    // Sepolia addresses
    IPoolManager constant POOL_MANAGER = IPoolManager(0x8C4BcBE6b9eF47855f97E675296FA3F6fafa5F1A);
    address constant POSITION_MANAGER = 0x1B1C77B606d13b09C84d1c7394B96b147bC03147;
    
    // Chainlink feeds
    address constant ETH_USD_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    
    // Deployed contracts (set after deployment or load from file)
    address public hook;
    address public coordinator;
    address public oracle;
    
    // Test tokens
    TestToken public tokenA;
    TestToken public tokenB;
    
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        
        vm.startBroadcast(deployerKey);
        
        // Load deployed addresses from environment or deploy new ones
        hook = vm.envOr("HOOK_ADDRESS", address(0));
        coordinator = vm.envOr("COORDINATOR_ADDRESS", address(0));
        oracle = vm.envOr("ORACLE_ADDRESS", address(0));
        
        console2.log("Deployer:", deployer);
        console2.log("Hook:", hook);
        console2.log("Coordinator:", coordinator);
        
        // 1. Deploy test tokens
        console2.log("\n=== Deploying Test Tokens ===");
        tokenA = new TestToken("Test Token A", "TKNA");
        tokenB = new TestToken("Test Token B", "TKNB");
        
        console2.log("TokenA:", address(tokenA));
        console2.log("TokenB:", address(tokenB));
        
        // Mint tokens to deployer
        tokenA.mint(deployer, 1_000_000 ether);
        tokenB.mint(deployer, 1_000_000 ether);
        console2.log("Minted 1M tokens each to deployer");
        
        // 2. Create pool with our hook
        console2.log("\n=== Creating Pool ===");
        
        // Sort currencies (lower address first)
        Currency currency0;
        Currency currency1;
        if (address(tokenA) < address(tokenB)) {
            currency0 = Currency.wrap(address(tokenA));
            currency1 = Currency.wrap(address(tokenB));
        } else {
            currency0 = Currency.wrap(address(tokenB));
            currency1 = Currency.wrap(address(tokenA));
        }
        
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 3000, // 0.3%
            tickSpacing: 60,
            hooks: IHooks(hook)
        });
        
        // Initialize pool at 1:1 price (sqrtPriceX96 for price = 1)
        uint160 sqrtPriceX96 = 79228162514264337593543950336; // sqrt(1) * 2^96
        
        POOL_MANAGER.initialize(poolKey, sqrtPriceX96);
        console2.log("Pool initialized at 1:1 price");
        
        // 3. Approve tokens
        console2.log("\n=== Setting up Approvals ===");
        tokenA.approve(POSITION_MANAGER, type(uint256).max);
        tokenB.approve(POSITION_MANAGER, type(uint256).max);
        tokenA.approve(address(POOL_MANAGER), type(uint256).max);
        tokenB.approve(address(POOL_MANAGER), type(uint256).max);
        console2.log("Tokens approved");
        
        // 4. Register tokens with oracle
        if (oracle != address(0)) {
            console2.log("\n=== Registering Token Oracles ===");
            OracleRegistry oracleRegistry = OracleRegistry(oracle);
            
            try oracleRegistry.setPriceFeed(address(tokenA), address(0), ETH_USD_FEED) {
                console2.log("TokenA registered with ETH/USD feed");
            } catch {
                console2.log("TokenA feed already registered or error");
            }
            
            try oracleRegistry.setPriceFeed(address(tokenB), address(0), ETH_USD_FEED) {
                console2.log("TokenB registered with ETH/USD feed");
            } catch {
                console2.log("TokenB feed already registered or error");
            }
        }
        
        vm.stopBroadcast();
        
        // Output for CLI to parse
        console2.log("\n=== DEPLOYMENT OUTPUT ===");
        console2.log("TOKEN_A=%s", address(tokenA));
        console2.log("TOKEN_B=%s", address(tokenB));
        console2.log("CURRENCY0=%s", Currency.unwrap(currency0));
        console2.log("CURRENCY1=%s", Currency.unwrap(currency1));
    }
}
