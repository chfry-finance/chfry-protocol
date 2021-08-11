// SPDX-License-Identifier: MIT
pragma solidity >=0.6.5 <0.8.0;

import "./libraries/Upgradable.sol";
import "./libraries/ConfigNames.sol";

contract FryerConfig is UpgradableProduct, UpgradableGovernance {
    uint256 public version = 1;
    event ConfigValueChanged(bytes32 _name, uint256 _old, uint256 _value);

    struct Config {
        uint256 minValue;
        uint256 maxValue;
        uint256 maxSpan;
        uint256 value;
        uint256 enable; // 0:disable, 1: enable
    }

    mapping(bytes32 => Config) public configs;
    uint256 public constant PERCENT_DENOMINATOR = 10000;
    address public constant ZERO_ADDRESS = address(0);

    constructor() public {
        // 50%
        _initConfig(ConfigNames.FRYER_LTV, 5000, 8000, 100, 5000);

        // 80%
        _initConfig(ConfigNames.FRYER_VAULT_PERCENTAGE, 2000, 9000, 500, 8000);

        // 5%
        _initConfig(ConfigNames.FRYER_HARVEST_FEE, 0, 1000, 100, 500);

        // 5%
        _initConfig(ConfigNames.FRYER_FLASH_FEE_PROPORTION, 0, 1000, 100, 6);
    }

    function _initConfig(
        bytes32 _name,
        uint256 _minValue,
        uint256 _maxValue,
        uint256 _maxSpan,
        uint256 _value
    ) internal {
        Config storage config = configs[_name];
        config.minValue = _minValue;
        config.maxValue = _maxValue;
        config.maxSpan = _maxSpan;
        config.value = _value;
        config.enable = 1;
    }

    function getConfig(bytes32 _name)
        external
        view
        returns (
            uint256 minValue,
            uint256 maxValue,
            uint256 maxSpan,
            uint256 value,
            uint256 enable
        )
    {
        Config memory config = configs[_name];
        minValue = config.minValue;
        maxValue = config.maxValue;
        maxSpan = config.maxSpan;
        value = config.value;
        enable = config.enable;
    }

    function getConfigValue(bytes32 _name) public view returns (uint256) {
        return configs[_name].value;
    }

    function changeConfig(
        bytes32 _name,
        uint256 _minValue,
        uint256 _maxValue,
        uint256 _maxSpan,
        uint256 _value
    ) external requireImpl returns (bool) {
        _initConfig(_name, _minValue, _maxValue, _maxSpan, _value);
        return true;
    }

    function changeConfigValue(bytes32 _name, uint256 _value)
        external
        requireGovernor
        returns (bool)
    {
        Config storage config = configs[_name];
        require(config.enable == 1, "DISABLE");
        require(
            _value <= config.maxValue && _value >= config.minValue,
            "OVERFLOW"
        );
        uint256 old = config.value;
        uint256 span = _value >= old ? (_value - old) : (old - _value);
        require(span <= config.maxSpan, "EXCEED MAX ADJUST SPAN");
        config.value = _value;
        emit ConfigValueChanged(_name, old, _value);
        return true;
    }

 
}
