// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {ProfitProver} from "./ProfitProver.sol";
import {HodlerBadgeNFT} from "./HodlerBadgeNFT.sol";

import {Proof} from "vlayer-0.1.0/Proof.sol";
import {Verifier} from "vlayer-0.1.0/Verifier.sol";

contract ProfitVerifier is Verifier {
    address public prover;
    mapping(address => bool) public claimed;
    HodlerBadgeNFT public reward;

    constructor(address _prover) {
        prover = _prover;
        reward = new HodlerBadgeNFT();
    }

    // We're now taking the profit as an *int256* since profit can be negative (loss).  Adjust the type accordingly.
    function claim(Proof calldata _proof, address _claimer, int256 _profit) public onlyVerified(prover, ProfitProver.calculateProfit.selector) {
        require(!claimed[_claimer], "Already claimed");

        // Define the profit threshold to receive the reward.  Adjust to your desired value.
        int256 PROFIT_THRESHOLD = 1000 * 10**18; // Example: 1000 tokens (assuming 18 decimals)

        // Check if the calculated profit is greater than or equal to the threshold
        if (_profit >= PROFIT_THRESHOLD) {
            claimed[_claimer] = true;
            reward.mint(_claimer);
        }
    }
}
