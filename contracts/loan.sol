pragma solidity ^0.8.10;

contract loan {
    struct Balances {
        uint256 collateral_balance; // notional amount held in the contract as collateral
        uint256 outstanding_balance; // the total amount currently owed (principal + interest) on the loan
    }

    Balances private balances;

    struct lendingTerms {
        address lender; // address of the issuing party (aka the lender)
        address borrower; // address of the borrowing party
        uint256 initial_principal; // the initial total notional of the loan issued
        uint256 issuance_time; // the time since epoch of the issuance of the loan.  This is the time that the initial withdrawal of any principal is made
        uint256 term; // term of the loan in seconds
        uint256 apr; // annual percentage rate
        uint256 collateral_req; // % of loan initial_principal required to be stored in the contract as collateral
        uint256 prepayment_penalty; // % of remaining outstanding_balance to charge as fee for paying early
        uint256 prepayment_period; // if prepayment_penalty != 0, the period of time in seconds after loan issuance that prepayment penalties are charged, must be < loan term.
        bool sliding_scale_prepayment_penalty; // A sliding scale for the prepayment_penalty, this reduces the % of the prepayment_penalty linearly as the time left in the prepayment period decreases.  The math is (time remaining in prepayment period / prepayment_period) * prepayment fee
        uint256 late_fee; // the total notional fee for a late payment (a payment made at a time > (issuance date + term + grace period))
        uint256 grace_period; // the period of time in seconds after issuance date + term that a borrower can repay the loan without incurring a late fee (interest is still accrued in this period)
    }

    lendingTerms private terms;

    constructor() {
        terms.lender = msg.sender;
    }

    modifier onlyLender() {
        require(
            msg.sender == terms.lender,
            "Only the owner of the contract can perform this operation"
        );
        _;
    }

    modifier onlyBorrower() {
        require(
            msg.sender == terms.borrower,
            "Only the borrower of the contract can perform this operation"
        );
        _;
    }

    function getTerms() external view returns (lendingTerms memory) {
        return terms;
    }

    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
        //total balance of the contract, note this also contains any collateral, so only the contracts balance - collateral is available to be withdrawn by the lender
    }

    function getCollateralBalance() external view returns (uint256) {
        return balances.collateral_balance;
    }

    function getOutstandingBalance() external view returns (uint256) {
        return balances.outstanding_balance;
    }

    function getSlidingScalePrepaymentFee() external view returns (uint256) {
        require(
            terms.issuance_time != 0,
            "loan must be issued before calling this method"
        );
        uint256 realized_prepayment_fee = ((((terms.issuance_time +
            terms.prepayment_period) - block.timestamp) /
            terms.prepayment_period) * terms.prepayment_penalty); // Prepayment fee percentage, multiply by payment to calculate total fee for a payment
        return realized_prepayment_fee;
    }

    function setTerms(
        address borrower,
        uint256 term,
        uint256 apr,
        uint256 collateral_req,
        uint256 prepayment_penalty,
        uint256 prepayment_period,
        bool sliding_scale_prepayment_penalty,
        uint256 late_fee,
        uint256 grace_period
    ) external onlyLender {
        require(term > 0, "term must be non-zero");
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
        terms.initial_principal = msg.value;
    }

    function allocateCollateral() external payable onlyBorrower {
        if (terms.collateral_req == 0) {
            revert("No collateral is necessary for this loan");
        }
        if (terms.initial_principal > 0) {
            revert("Loan must be funded before collateral is allocated");
        }
        if (msg.value >= (terms.collateral_req * terms.initial_principal)) {
            balances.collateral_balance = msg.value;
        } else {
            revert(
                "Collateral allocated must be greater than or equal to the collateral requirement * initial principal of the loan"
            );
        }
    }

    function issueLoan() external payable onlyLender {
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

    bool late_fee_charged;

    function determineFees(uint256 current_time, uint256 payment) private {
        uint256 realized_prepayment_fee;
        uint256 year = 31104000;

        balances.outstanding_balance +=
            ((terms.apr / year) * (block.timestamp - terms.issuance_time)) *
            terms.initial_principal;
        if (current_time > (terms.issuance_time + terms.term)) {
            if (late_fee_charged == false) {
                balances.outstanding_balance += terms.late_fee;
                late_fee_charged = true;
            }
        }

        if (terms.prepayment_penalty > 0) {
            if (
                (terms.issuance_time + terms.prepayment_period) < current_time
            ) {
                require(
                    payment <= balances.outstanding_balance,
                    "payment is larger than outstanding balance"
                );
            } else if (
                (terms.issuance_time + terms.prepayment_period) > current_time
            ) {
                if (terms.sliding_scale_prepayment_penalty == true) {
                    realized_prepayment_fee =
                        ((((terms.issuance_time + terms.prepayment_period) -
                            current_time) / terms.prepayment_period) *
                            terms.prepayment_penalty) *
                        msg.value;
                } else {
                    realized_prepayment_fee =
                        terms.prepayment_penalty *
                        payment;
                }

                require(
                    payment <=
                        balances.outstanding_balance + realized_prepayment_fee,
                    "payment is larger than outstanding balance + the prepayment fee"
                );

                balances.outstanding_balance += realized_prepayment_fee;
            }
        }
        balances.outstanding_balance -= payment;
    }

    function makePayment() external payable onlyBorrower {
        uint256 current_time = block.timestamp;
        uint256 payment = msg.value;
        determineFees(current_time, payment);
        withdraw();
    }

    function withdraw() public payable onlyLender {
        uint256 withdrawable_amount = address(this).balance -
            balances.collateral_balance;
        (bool sent, bytes memory data) = terms.lender.call{
            value: withdrawable_amount
        }("");
        require(sent, "Failed to send payment");
    }
}
