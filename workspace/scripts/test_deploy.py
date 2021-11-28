from brownie import loan, accounts
import time
import json

def deploy():
    deployed = loan.deploy({'from': accounts[0]})
    setTerms(deployed, accounts[1])
    return deployed

def getTerms(deployed_contract):
    terms = deployed_contract.getTerms()
    return terms

def setTerms(deployed, borrower):
    deployed.setTerms(borrower, 100000, 5167250000000000000, 0, 0, 0, 0, 0, 0, 0)

def format_terms(deployed_contract):
    terms = getTerms(deployed_contract)

    terms_defs = ['lender',
                    'borrower',
                    'principal',
                    'apr',
                    'collateral_req',
                    'late_fee',
                    'prepayment_penalty',
                    'prepayment_period',
                    'issuance_time',
                    'term',
                    'grace_period',
                    'time_before_default'
                    'sliding_scale_prepayment_penalty'
                    ]

    terms_dict = {}
    i = 0
    for label in terms_defs:
        terms_dict[label] = terms[i]
        i+=1 

    return terms_dict

def fundAndIssueLoan(deployed):
    deployed.fundAndIssueLoan({'from': accounts[0], 'value': 2000000000000000000})


def main():
    deployed = deploy()

    time.sleep(.5)

    fundAndIssueLoan(deployed)

    time.sleep(.5)

    print(format_terms(deployed))

    value = deployed.getOutstandingBalance()
    deployed.makePayment({'from': accounts[1], 'value': value})

    time.sleep(.5)

    print(deployed.getOutstandingBalance())
    print(format_terms(deployed))




    

    