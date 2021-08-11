//SPDX-License-Identifier: MIT
pragma solidity >=0.6.5 <0.8.0;

library ConfigNames {
    bytes32 public constant FRYER_LTV = bytes32("FRYER_LTV");
    bytes32 public constant FRYER_HARVEST_FEE = bytes32("FRYER_HARVEST_FEE");
    bytes32 public constant FRYER_VAULT_PERCENTAGE =
        bytes32("FRYER_VAULT_PERCENTAGE");

    bytes32 public constant FRYER_FLASH_FEE_PROPORTION =
        bytes32("FRYER_FLASH_FEE_PROPORTION");

    bytes32 public constant PRIVATE = bytes32("PRIVATE");
    bytes32 public constant STAKE = bytes32("STAKE");
}
