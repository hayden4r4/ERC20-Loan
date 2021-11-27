pragma solidity ^0.8.10;

/// @title ERC20-Loan
/// @author Hayden Rose
/// github: https://github.com/hayden4r4/ERC20-Loan

import {ABDKMathQuad} from "./ABDKMathQuad.sol";

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
        uint256 principal; /// @param principal the initial total notional of the loan issued
        uint256 issuance_time; /// @param issuance_time the time since epoch of the issuance of the loan.  This is the time that the initial withdrawal of any principal is made
        uint256 term; /// @param term term of the loan in seconds
        uint256 apr; /// @param apr annual percentage rate in decimal format * 10**18
        uint256 collateral_req; /// @param collateral_req % of loan principal required to be stored in the contract as collateral in decimal format * 10**18
        uint256 prepayment_penalty; /// @param prepayment_penalty % of remaining outstanding_balance to charge as fee for paying early in decimal format * 10**18
        uint256 prepayment_period; /// @param prepayment_period if prepayment_penalty != 0, the period of time in seconds after loan issuance that prepayment penalties are charged, must be < loan term.
        bool sliding_scale_prepayment_penalty; /// @param sliding_scale_prepayment_penalty A sliding scale for the prepayment_penalty, this reduces the % of the prepayment_penalty linearly as the time left in the prepayment period decreases.  The math is (time remaining in prepayment period / prepayment_period) * prepayment fee
        uint256 late_fee; /// @param late_fee the total notional fee in wei for a late payment (a payment made at a time > (issuance date + term + grace period))
        uint256 grace_period; /// @param grace_period the period of time in seconds after issuance date + term that a borrower can repay the loan without incurring a late fee (interest is still accrued in this period)
        uint256 default_expiry; /// @param default_period the time (in seconds) after loan term expiration in which default is entered and collateral is seized
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

    function changeLender(address new_lender) public onlyLender {
        /// @dev Allows the lender to transfer ownership of the loan
        terms.lender = new_lender;
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

    function getOutstandingBalance() public view returns (uint256) {
        /// @dev Returns the outstanding balance (principal + interest + fees) of the loan
        /// @return uint256 outstanding balance of the loan (principal + interest + fees) in wei
        return balances.outstanding_balance + getFees();
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
        uint256 grace_period, // seconds
        uint256 default_expiry // seconds
    ) external onlyLender {
        /// @dev Sets the terms of the loan
        /// @notice The term of the loan must be greater than 0. Terms are immutable after loan is issued.
        require(
            balances.outstanding_balance == 0,
            "Terms cannot be changed after loan has been issued"
        );
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
        terms.default_expiry = default_expiry;
    }

    function fundLoan() external payable onlyLender {
        /// @dev Sends value to fund the loan, must be performed before terms are set, only lender can call
        terms.principal = msg.value;
    }

    function allocateCollateral() external payable onlyBorrower {
        /// @dev Sends value to allovate collateral for the loan, only borrower can call
        require(
            terms.collateral_req == 0,
            "No collateral is necessary for this loan"
        );
        require(
            terms.principal > 0,
            "Loan must be funded before collateral is allocated"
        );
        bytes16 collateral_amount = ABDKMathQuad.mul(
            ABDKMathQuad.fromUInt(terms.collateral_req).div(ten18),
            ABDKMathQuad.fromUInt(terms.principal)
        );
        require(
            ABDKMathQuad.fromUInt(msg.value) == collateral_amount,
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
        require(terms.principal != 0, "Loan must be funded before issuing");
        if (terms.collateral_req > 0) {
            require(
                balances.collateral_balance > 0,
                "Collateral must be allocated before issuing loan"
            );
        }
        (bool sent, bytes memory data) = terms.borrower.call{
            value: terms.principal
        }("");
        require(sent, "Failed to send payment");

        terms.issuance_time = block.timestamp;
        balances.outstanding_balance = terms.principal;
    }

    using ABDKMathQuad for bytes16;
    uint256 private YEAR = 31556952; /// seconds in a year, constant
    bytes16 private immutable ten18 = ABDKMathQuad.fromUInt(10**18);
    bytes16 private immutable YEAR_ = ABDKMathQuad.fromUInt(YEAR);

    function getFees() public view returns (uint256) {
        /** @dev Calculates borrower fees. The math here is done using
        the ABDKMathQuah library. The lack of floats greatly complicates
        the math here and increases gas fees, but it is all very straightforward
        and simple alculations and should be accurate with the library's safeguards.
        */
        /// @return Returns the borrower total fee in wei. uint256 data type.
        uint256 current_time = block.timestamp;
        uint256 due = terms.issuance_time + terms.term;
        uint256 prepayment_window = terms.issuance_time +
            terms.prepayment_period;
        bytes16 fee;

        /// @dev Late Fee
        if (
            (terms.late_fee != 0) && ((due + terms.grace_period) < current_time)
        ) {
            fee = ABDKMathQuad.add(fee, ABDKMathQuad.fromUInt(terms.late_fee));
        }

        /// @dev Intereest Fee
        /// @notice Uses simple interest calculation
        bytes16 interest_per_second = ABDKMathQuad
            .fromUInt(terms.apr)
            .div(ten18)
            .div(YEAR_);
        bytes16 total_interest_rate = ABDKMathQuad
            .fromUInt(current_time - terms.issuance_time)
            .mul(interest_per_second); /// to - from
        bytes16 total_interest_fee = ABDKMathQuad.fromUInt(terms.principal).mul(
            total_interest_rate
        );
        fee = ABDKMathQuad.add(fee, total_interest_fee);

        /// @dev Prepayment Fee
        /// @notice Decides whether to use a sliding prepayment penalty and then calculates it
        if (
            (terms.prepayment_period != 0) && (current_time < prepayment_window)
        ) {
            if (terms.sliding_scale_prepayment_penalty) {
                bytes16 time_left_in_window = ABDKMathQuad.fromUInt(
                    prepayment_window - current_time
                );
                bytes16 sliding_scale_fee = ABDKMathQuad
                    .div(
                        time_left_in_window,
                        ABDKMathQuad.fromUInt(terms.prepayment_period)
                    )
                    .mul(ABDKMathQuad.fromUInt(terms.prepayment_penalty))
                    .mul(ABDKMathQuad.fromUInt(terms.principal).div(ten18));
                fee = ABDKMathQuad.add(fee, sliding_scale_fee);
            } else {
                bytes16 prepayment_fee = ABDKMathQuad.mul(
                    ABDKMathQuad.fromUInt(terms.principal),
                    ABDKMathQuad.fromUInt(terms.prepayment_penalty).div(ten18)
                );
                fee = ABDKMathQuad.add(fee, prepayment_fee);
            }
        }
        return fee.toUInt();
    }

    function makePayment() external payable onlyBorrower {
        /// @dev Method to send value to contract to make payment on loan, can only be called by borrower
        /// @notice Sending a payment equal to the return value of the getOutstandingBalance method is the ideal payment flow
        uint256 payment = msg.value;
        balances.outstanding_balance = getOutstandingBalance();
        require(
            payment == balances.outstanding_balance,
            "Payment must be equal to the outstanding balance (principal + interest + fees)"
        );
        /// @dev Automatically withdrawals payment made to the contract back into the lender's wallet
        (bool sent, bytes memory data) = terms.lender.call{
            value: address(this).balance
        }("");
        freeCollateral();
    }

    function freeCollateral() internal onlyBorrower {
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

    function seizeCollateral() external payable onlyLender {
        /// @dev Allows lender to seize collateral if term + default_expiry is past, only lender can call
        require(
            (terms.term + terms.issuance_time + terms.default_expiry) <
                block.timestamp,
            "Collateral can only be seized once loan is in default"
        );

        require(
            balances.collateral_balance > 0,
            "There is currently no collateral to seize"
        );

        uint256 withdrawable_amount = address(this).balance -
            balances.collateral_balance;
        (bool sent, bytes memory data) = terms.lender.call{
            value: withdrawable_amount
        }("");
        require(sent, "Failed to withdraw");
    }

    function withdraw() public payable onlyLender {
        /** @dev Method to withdraw payments made back to the lender's wallet.
            This method should be uneccessary as payments made should be automatically
            withdrawn to the lender's wallet.  This method serves as a failsafe and
            can only be called by the lender.
        */
        require(
            address(this).balance > 0,
            "Contract balance is 0, there is nothing available to withdraw"
        );
        uint256 withdrawable_amount = address(this).balance -
            balances.collateral_balance;
        (bool sent, bytes memory data) = terms.lender.call{
            value: withdrawable_amount
        }("");
        require(sent, "Failed to withdraw");
    }
}
