pragma solidity =0.5.16;

import './Uniswap/interfaces/IUniswapFactory.sol';
import './Uniswap/UniswapPair.sol';

contract BoleroBase is IUniswapFactory {
    address public feeTo; // L'adresse où les fees vont être envoyés.
    address public feeToSetter; // L'adresse qui a accès au changement des fees

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs; // Stockage des pairs dans ce tableau. 

    event PairCreated(address indexed token0, address indexed token1, address pair, uint); // Evenement de la pair créée

    constructor(address _feeToSetter) public {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    // Fonction qui récupère toutes les fonctionnalités UniswapPair
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, 'UniswapV2: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'UniswapV2: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(UniswapPair).creationCode; // Tous
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IUniswapPair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }
}
