// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import {Proof} from "vlayer-0.1.0/Proof.sol";
import {Prover} from "vlayer-0.1.0/Prover.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract ProfitProver is Prover {
    IERC20 public immutable TOKEN;
    uint256 public immutable STARTING_BLOCK;
    uint256 public immutable ENDING_BLOCK;
    uint256 public immutable STEP;
    uint256 public immutable FEE_PERCENTAGE = 5;

    event TransactionProcessed(address indexed owner, uint256 blockNumber, uint256 amount, string transactionType);
    event ProfitCalculated(address indexed owner, uint256 profit);

    struct Transaction {
        uint256 blockNumber;
        uint256 amount; // Amount of token bought or sold. Positive for buys, negative for sells
        string transactionType; // "buy" or "sell"
    }

    constructor(IERC20 _token, uint256 _startBlockNo, uint256 _endingBlockNo, uint256 _step) {
        TOKEN = _token;
        STARTING_BLOCK = _startBlockNo;
        ENDING_BLOCK = _endingBlockNo;
        STEP = _step;
    }

    function calculateProfit(address _owner) public returns (Proof memory, address, int256) {
        int256 profit = 0;  // Use int256 to handle potential negative profit
        Transaction[] memory transactions = getTransactions(_owner);

        // Logic to calculate profit based on buys and sells, accounting for fees
        uint256 buyCost = 0;
        uint256 sellRevenue = 0;

        for (uint256 i = 0; i < transactions.length; i++) {
            Transaction memory tx = transactions[i];
            if (keccak256(bytes(tx.transactionType)) == keccak256(bytes("buy"))) {
                // Apply fee to buy amount
                uint256 feeAmount = tx.amount * FEE_PERCENTAGE / 10000;
                buyCost = buyCost + tx.amount - feeAmount;

                emit TransactionProcessed(_owner, tx.blockNumber, tx.amount, tx.transactionType);

            } else if (keccak256(bytes(tx.transactionType)) == keccak256(bytes("sell"))) {
                // Apply fee to sell amount
                uint256 feeAmount = tx.amount * FEE_PERCENTAGE / 10000;
                sellRevenue = sellRevenue + tx.amount - feeAmount;

                emit TransactionProcessed(_owner, tx.blockNumber, tx.amount, tx.transactionType);

            }
        }
        profit = int256(sellRevenue) - int256(buyCost);

        emit ProfitCalculated(_owner, uint256(profit));

        return (proof(), _owner, profit);
    }

    // Simpler getTransactions that uses logs and requires the external service to provide all transactions
    // This is a tradeoff - it reduces on-chain logic but depends on the reliability of an external service.
    function getTransactions(address _owner) internal returns (Transaction[] memory) {
        // !!! WARNING !!!: This example uses mock data.  You MUST replace this with
        // a real implementation.  See the previous responses for options like TheGraph,
        // Etherscan API, or custom indexing.

        // Simulate external source providing transactions for _owner
        //  This is where your TheGraph/Etherscan/Custom logic goes
        //  transactions are ALREADY formatted correctly.
        //  Crucially, the transactionType field MUST be correct.
        Transaction[] memory transactions = new Transaction[](2);

        transactions[0] = Transaction({
            blockNumber: STARTING_BLOCK + 1,
            amount: 100,
            transactionType: "buy"
        });

        transactions[1] = Transaction({
            blockNumber: ENDING_BLOCK - 1,
            amount: 120,
            transactionType: "sell"
        });

        return transactions;
    }

    //Example of more complext Transaction
    // getTransactions function using Transfer events (requires event indexing)
    /*
    function getTransactions(address _owner) internal returns (Transaction[] memory) {
        uint256 transferEventsCount = getTransferEventsCount(_owner);

        Transaction[] memory transactions = new Transaction[](transferEventsCount);
        uint256 transactionIndex = 0;

        for (uint256 blockNo = STARTING_BLOCK; blockNo <= ENDING_BLOCK; blockNo += STEP) {
            setBlock(blockNo);

            // Get all Transfer events in this block for this owner
            // Replace the following with your actual logic to fetch events
            // Example: Use external service/indexers to query logs for Transfer event
            // event Transfer(address indexed from, address indexed to, uint256 value);

            // Simulate Transfer events (remove this in production)
            address from = _owner;
            address to = address(this);
            uint256 value = 10 * 10**TOKEN.decimals();

            // Check if event "from" is the user, it means the token was sold, so negative amount
            if (from == _owner) {
                transactions[transactionIndex] = Transaction({
                    blockNumber: blockNo,
                    amount: value,
                    transactionType: "sell"
                });
                transactionIndex++;
            }

            // Check if event "to" is the user, it means the token was bought, so positive amount
            if (to == _owner) {
                transactions[transactionIndex] = Transaction({
                    blockNumber: blockNo,
                    amount: value,
                    transactionType: "buy"
                });
                transactionIndex++;
            }

        }

        // Trim the array if less than transferEventsCount events found
        assembly {
                mstore(transactions, transactionIndex)  // set the length of the array to `transactionIndex`
            }

        return transactions;

    }
    */

    /*
    // Helper function to count Transfer events for the owner
    function getTransferEventsCount(address _owner) internal returns (uint256) {
        uint256 count = 0;
        for (uint256 blockNo = STARTING_BLOCK; blockNo <= ENDING_BLOCK; blockNo += STEP) {
            setBlock(blockNo);

            // Get all Transfer events in this block for this owner
            //  (IMPLEMENT: Your logic using external data source for querying blockchain data)
            // Count Transfer events where either 'from' or 'to' is the specified address
            //
        }

        // REMOVE, this is a placeholder
        //return 2;
        return count;  // Replace with calculated count
    }
    */
}
