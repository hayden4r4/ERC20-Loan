pragma solidity ^0.8.10;

/// @title ERC20-Loan
/// @author Hayden Rose
/// github: https://github.com/hayden4r4/ERC20-Loan

contract loan {
    /// @dev Contains main loan contract
    /** @notice This is a standard 2-party balloon payment contract,
       full principal + interst is due at end of loan term.
       Prepayments and late payments can be penalized if set
       by the lender in the loan terms.  The borrower of the loan
       is initialized when the terms are set, only the borrower can
       withdraw principal and make payment on the loan.
    */

    struct Balances {
        /// @dev Contains balances for the contract
        uint256 collateral_balance; /// @param collateral_balance notional amount held in the contract as collateral
        uint256 outstanding_balance; /// @param outstanding_balance the total amount currently owed (principal + interest) on the loan
    }

    Balances private balances;

    struct LendingTerms {
        /// @dev The Terms of the contract
        /** @notice all percentages are in 10**4 format, meaning
            only up to 4 decimals are supported in order to avoid
            truncating errors.  So 6.54% would be inputted as 65400.
            All notional values are in wei. All time values are in seconds.
        */
        address lender; /// @param lender address of the issuing party (aka the lender)
        address borrower; /// @param borrower address of the borrowing party
        uint256 initial_principal; /// @param initial_principal the initial total notional of the loan issued
        uint256 issuance_time; /// @param issuance_time the time since epoch of the issuance of the loan.  This is the time that the initial withdrawal of any principal is made
        uint256 term; /// @param term term of the loan in seconds
        uint256 apr; /// @param apr annual percentage rate in 10**4 format
        uint256 collateral_req; /// @param collateral_req % of loan initial_principal required to be stored in the contract as collateral in 10**4 format
        uint256 prepayment_penalty; /// @param prepayment_penalty % of remaining outstanding_balance to charge as fee for paying early in 10**4 format
        uint256 prepayment_period; /// @param prepayment_period if prepayment_penalty != 0, the period of time in seconds after loan issuance that prepayment penalties are charged, must be < loan term.
        bool sliding_scale_prepayment_penalty; /// @param sliding_scale_prepayment_penalty A sliding scale for the prepayment_penalty, this reduces the % of the prepayment_penalty linearly as the time left in the prepayment period decreases.  The math is (time remaining in prepayment period / prepayment_period) * prepayment fee
        uint256 late_fee; /// @param late_fee the total notional fee in wei for a late payment (a payment made at a time > (issuance date + term + grace period))
        uint256 grace_period; /// @param grace_period the period of time in seconds after issuance date + term that a borrower can repay the loan without incurring a late fee (interest is still accrued in this period)
    }

    LendingTerms private terms;

    constructor() {
        /// @dev The constructor, sets lender variable to the address of the wallet that created the contract
        terms.lender = msg.sender;
    }

    modifier onlyLender() {
        /// @dev A modifier to determine if the sender's address is the lender, if not returns error
        require(
            msg.sender == terms.lender,
            "Only the owner of the contract can perform this operation"
        );
        _;
    }

    modifier onlyBorrower() {
        /// @dev A modifier to determine if the sender's address is the borrower, if not returns error
        require(
            msg.sender == terms.borrower,
            "Only the borrower of the contract can perform this operation"
        );
        _;
    }

    function getTerms() external view returns (LendingTerms memory) {
        /// @dev Returns the terms of the loan set by the lender
        /// @return LendingTerms A struct containing the terms of the loan
        return terms;
    }

    function getContractBalance() external view returns (uint256) {
        /// @dev Returns the total balance currently in the contract
        /// @notice //total balance of the contract, note this also contains any collateral, so only the contracts balance - collateral is available to be withdrawn by the lender
        /// @return uint256 total balance currently held in the contract
        return address(this).balance;
    }

    function getCollateralBalance() external view returns (uint256) {
        /// @dev Returns the balance of collateral currently held in the contract
        /// @return uint256 balance of collateral in the contract
        return balances.collateral_balance;
    }

    function getOutstandingBalance() external view returns (uint256) {
        /// @dev Returns the outstanding balance (principal + interest + fees) of the loan
        /// @return uint256 outstanding balance of the loan (principal + interest + fees) in wei
        return balances.outstanding_balance;
    }

    function getSlidingScalePrepaymentFee() external view returns (uint256) {
        /** @dev Calculates the sliding scale prepayment fee if set to true in loan terms.
            This is a fee which declines linearlly to 0 as the prepayment period progresses.
        */
        /// @return uint256 the calculated prepayment fee
        require(
            terms.issuance_time != 0,
            "loan must be issued before calling this method"
        );
        uint256 realized_prepayment_fee = (((((terms.issuance_time +
            terms.prepayment_period) - block.timestamp) /
            terms.prepayment_period) * terms.prepayment_penalty) / 100); // Prepayment fee percentage, multiply by payment to calculate total fee for a payment
        return realized_prepayment_fee;
    }

    function setTerms(
        address borrower, // address
        uint256 term, // seconds
        uint256 apr, // % * 10**4
        uint256 collateral_req, // % * 10**4
        uint256 prepayment_penalty, // % * 10**4
        uint256 prepayment_period, // seconds
        bool sliding_scale_prepayment_penalty, // bool
        uint256 late_fee, // wei
        uint256 grace_period // seconds
    ) external onlyLender {
        /// @dev Sets the terms of the loan
        /// @notice The term of the loan must be greater than 0
        require(term > 0, "term must be greater than zero");
        terms.borrower = borrower;
        terms.term = term;
        terms.apr = apr;
        terms.collateral_req = collateral_req;
        terms.prepayment_penalty = prepayment_penalty;
        terms.prepayment_period = prepayment_period;
        terms
            .sliding_scale_prepayment_penalty = sliding_scale_prepayment_penalty;
        terms.late_fee = late_fee;
        terms.grace_period = grace_period;
    }

    function fundLoan() external payable onlyLender {
        /// @dev Sends value to fund the loan, must be performed before terms are set, only lender can call
        terms.initial_principal = msg.value;
    }

    function allocateCollateral() external payable onlyBorrower {
        /// @dev Sends value to allovate collateral for the loan, only borrower can call
        require(
            terms.collateral_req == 0,
            "No collateral is necessary for this loan"
        );
        require(
            terms.initial_principal > 0,
            "Loan must be funded before collateral is allocated"
        );
        require(
            msg.value >=
                ((terms.collateral_req * terms.initial_principal) / 100),
            "Collateral allocated must be greater than or equal to the collateral requirement * initial principal of the loan"
        );
        balances.collateral_balance = msg.value;
    }

    function issueLoan() external payable onlyLender {
        /** @dev Issues the loan by sending the funds to the borrower, can only be called by lender
            Loan must be funded, terms must be set, and if collateral is required, collateral must be allocated
            before issuing the loan.
        */
        require(
            terms.borrower != address(0),
            "A borrower must be assigned before issuing loan"
        );
        require(
            terms.initial_principal != 0,
            "Loan must be funded before issuing"
        );
        if (terms.collateral_req > 0) {
            require(
                balances.collateral_balance > 0,
                "Collateral must be allocated before issuing loan"
            );
        }
        (bool sent, bytes memory data) = terms.borrower.call{
            value: terms.initial_principal
        }("");
        require(sent, "Failed to send payment");

        terms.issuance_time = block.timestamp;
        balances.outstanding_balance = terms.initial_principal;
    }

    bool private late_fee_charged;

    function determineFees(uint256 current_time, uint256 payment) private {
        /** @dev Determines the fees if any will be added to the outstanding balance. Called upon payment by borrower.
            The math on this is to multiply the apr by 10**12, allowing a divide by the number of seconds in 360 days in int format.
            This is multiplied by the length of time the loan has been issued (in seconds), and then multiplied by the intial principal
            to determine the total interest due.  This is then divided back by 10**12 and added to the outstanding balance.
        */
        uint256 realized_prepayment_fee; /// @param realized_prepayment_fee the total prepayment fee realized by the borrower
        uint256 YEAR = 31104000; /// @param YEAR number of seconds in 360 days

        balances.outstanding_balance +=
            ((((terms.apr * (10**12)) / YEAR) *
                (block.timestamp - terms.issuance_time)) *
                terms.initial_principal) /
            (10**12);
        if (current_time > (terms.issuance_time + terms.term)) {
            /// @dev if late fees have already been charged, they can not be charged again, this is a failsafe to prevent reissuance of late fees and is probably unneccessary
            if (late_fee_charged == false) {
                balances.outstanding_balance += terms.late_fee;
                late_fee_charged = true;
            }
        }

        if (terms.prepayment_penalty > 0) {
            /// @dev if prepayment penalty is greater than 0 then calculates prepayment penalty
            if (
                (terms.issuance_time + terms.prepayment_period) <= current_time
            ) {
                require(
                    payment == balances.outstanding_balance,
                    "payment is larger than outstanding balance"
                );
            } else {
                if (terms.sliding_scale_prepayment_penalty == true) {
                    realized_prepayment_fee =
                        (((((terms.issuance_time + terms.prepayment_period) -
                            current_time) / terms.prepayment_period) *
                            terms.prepayment_penalty) * payment) /
                        100;
                } else {
                    realized_prepayment_fee =
                        (terms.prepayment_penalty * payment) /
                        100;
                }

                require(
                    payment <=
                        balances.outstanding_balance + realized_prepayment_fee,
                    "payment is larger than outstanding balance + the prepayment fee"
                );

                balances.outstanding_balance += realized_prepayment_fee;
            }
        }
        balances.outstanding_balance -= payment; /// subtracts payment from outstanding balance
    }

    function makePayment() external payable onlyBorrower {
        /// @dev Method to send value to contract to make payment on loan, can only be called by borrower
        uint256 current_time = block.timestamp;
        uint256 payment = msg.value;
        determineFees(current_time, payment);
        freeCollateral();
        /// @dev Automatically withdrawals payment made to the contract back into the lender's wallet
        (bool sent, bytes memory data) = terms.lender.call{
            value: address(this).balance
        }("");
    }

    function freeCollateral() public payable onlyBorrower {
        /// @dev Frees the collateral back to the borrowers wallet, can only be called by borrower internally
        require(
            balances.outstanding_balance <= 0,
            "Cannot free collateral while outstanding balance > 0"
        );
        (bool sent, bytes memory data) = terms.lender.call{
            value: balances.collateral_balance
        }("");
        require(sent, "Failed to withdraw collateral");
    }

    function withdraw() public payable onlyLender {
        /** @dev Method to withdraw payments made back to the lender's wallet.
            This method should be uneccessary as payments made should be automatically
            withdrawn to the lender's wallet.  This method serves as a failsafe and
            can only be called by the lender.
        */
        uint256 withdrawable_amount = address(this).balance -
            balances.collateral_balance;
        (bool sent, bytes memory data) = terms.lender.call{
            value: withdrawable_amount
        }("");
        require(sent, "Failed to withdraw");
    }
}
