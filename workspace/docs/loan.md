## `loan`





### `onlyLender()`





### `onlyBorrower()`






### `getTerms() → struct loan.LendingTerms` (external)





### `getContractBalance() → uint256` (external)





### `getCollateralBalance() → uint256` (external)





### `getOutstandingBalance() → uint256` (external)





### `getSlidingScalePrepaymentFee() → uint256` (external)





### `setTerms(address borrower, uint256 term, uint256 apr, uint256 collateral_req, uint256 prepayment_penalty, uint256 prepayment_period, bool sliding_scale_prepayment_penalty, uint256 late_fee, uint256 grace_period)` (external)





### `fundLoan()` (external)





### `allocateCollateral()` (external)





### `issueLoan()` (external)





### `makePayment()` (external)





### `freeCollateral()` (public)





### `withdraw()` (public)







### `Balances`


uint256 collateral_balance


uint256 outstanding_balance


### `LendingTerms`


address lender


address borrower


uint256 initial_principal


uint256 issuance_time


uint256 term


uint256 apr


uint256 collateral_req


uint256 prepayment_penalty


uint256 prepayment_period


bool sliding_scale_prepayment_penalty


uint256 late_fee


uint256 grace_period



