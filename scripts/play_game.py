from brownie import CrowdConnectFourV1, accounts
from brownie.exceptions import VirtualMachineError
import numpy as np
import json
col_array = [0, 1, 2, 3, 4, 5, 6]

json.load(open('build/contracts/CrowdConnectFourV1.json'))

def main():
    for i in range(20):
        accounts.add()
    c4 = CrowdConnectFourV1.deploy({'from': accounts[0]})
    # c4 = ConnectFourV1.at('0x9900faCcc7C5C3565cbe3Cd957D57fb9EcF032bE')
    current_rount_id = c4.globalGameId()
    tx = c4.stake(current_rount_id, 0, {'from': accounts[0], 'value': 10**14})
    print(tx.events)
    tx = c4.stake(current_rount_id, 0, {'from': accounts[1], 'value': 10**15})
    print(tx.events)



    tx = c4.stake(current_rount_id, 1, {'from': accounts[2], 'value': 10**14})
    print(tx.events)
    tx = c4.stake(current_rount_id, 1, {'from': accounts[3], 'value': 10**15})
    print(tx.events)
    # make_vote(c4=c4, accounts=accounts, gameid=1)
    # make_vote(c4=c4, accounts=accounts, gameid=1)
    for i in range(2):
        valid_moves = c4.getValidMoves(1)
        rand_col = np.random.choice(a=col_array, p=(valid_moves)/np.sum(valid_moves))
        tx = c4.vote(current_rount_id, rand_col, {'from': accounts[i]})
        print(tx.events)
    for i in range(2, 2000):
        try:
            current_rount_id = c4.globalGameId()
            current_move_id = c4.globalMoveId()
            valid_moves = c4.getValidMoves(current_rount_id)
            print(current_move_id)
            rand_col = np.random.choice(a=col_array, p=(valid_moves)/np.sum(valid_moves))
            tx = c4.vote(current_rount_id, rand_col, {'from': accounts[i%20]})
            print(tx.events)
            if 'GameWon' in tx.events:
                for acc in accounts:
                    claimable = c4.claimable(current_rount_id, acc.address)
                    print(current_rount_id, acc.address, claimable)
                    if claimable:
                        tx = c4.claim([current_rount_id])
                        print(tx.events)
                raise
        except VirtualMachineError:
            pass

    print(c4.getBoards(current_rount_id))
    # game = c4.getGame(1)
    # valid_moves = c4.getValidMoves(1)
    # print(valid_moves)
    # print(game)

    return 0

def make_vote(c4, accounts, gameid):
    c4.vote(gameid, 1, {'from': accounts[0]})
    votes = c4.getColVotes()
    print(votes)
    c4.vote(gameid, 1, {'from': accounts[1]})
    votes = c4.getColVotes()
    print(votes)
    c4.vote(gameid, 1, {'from': accounts[2]})
    votes = c4.getColVotes()
    print(votes)
