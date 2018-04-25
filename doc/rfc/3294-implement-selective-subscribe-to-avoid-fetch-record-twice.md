# Replication: do not fetch records twice in a full mesh

* **Status**: In progress
* **Start date**: 25-04-2018
* **Authors**: Konstantin Belyavskiy @kbelyavs k.belyavskiy@tarantool.org, Georgy Kirichenko @georgy georgy@tarantool.org, Konstantin Osipov @kostja kostja@tarantool.org
* **Issues**: \[#3294\](https://github.com/tarantool/tarantool/issues/3294)

## Summary

replication: do not fetch records twice in a full mesh

## Background and motivation

Extend IPROTO_SUBSCRIBE command with a list of server ids for which SUBSCRIBE should fetch changes. In a full mesh configuration, only download records originating from the immediate peer. Do not download the records from other peers twice.

For example, imagine a full mesh of 3 replicas. Currently each Tarantool instance will download from all peers all records in their WAL excepts records with instance id equal to the self instance id. Instead, it could send a subscribe request to its peers with server ids which are not present in other subscribe requests.

## Implementation

After issuing IPROTO_REQUEST_VOTE to all peers we know a map of server ids, their peers and their vclocks. Sort the map by server id. Iterate over each server in the list of peers, and assign its  id to this server's SUBSCRIBE request. Assign all the remaining ids in \_cluster table to the last peer (alternatively, if there are many ids in the remainder, keep going through the list of server and assign "orphan" ids in round-robin fashion).
Issue the subscribe request.

After this feature is implemented, each time a server responsible feeding more than 1 server id is dropped, we need to re-subscribe to some other peer and reassign the dropped ids to that peer. Each time a server is connected again, we need to rebalance again.

## Proposal design

Implement subscription daemon (a script in Lua), which tracks changes in \_cluster table and appliers state. This daemon is responsible for reassigning logic.
Each applier has a list of UUIDs to subscribe. So daemon first get a list of UUIDs, then iterates through a list of appliers and get all their UUIDs performing two checks:
1. First, that for each UUIDs exists connected applier with this UUID in his list. If UUID has no associated applier, mark it as orphan and add to orphan list. Assign every orphan UUID to last applier and issues SUBSCRIBE request with a list of it's own UUIDs and the orphan ones.
2. Second, if applier is connected again, then daemon should reassign correspondent UUIDs back to this applier, so it issues SUBSCRIBE for all affected appliers.

## Detailed design

To make this happen, the following changes are required:
1. Extend IPROTO_SUBSCRIBE command with a list of server UUIDs for which SUBSCRIBE should fetch changes. Also suggest to add a new field to struct applier to store this list. By default issuing SUBSCRIBE with empty list which means no filtering at all.
2. In relay use this list of UUIDs as a white list filter. On subsrcribe we can fill a table of ids from these UUIDs and compare it with id in every record. By default transmit all records, unless SUBSCRIBE was done with at least one server id. In latter case drop all records except originating from peers from this list.
3. Assigning ids to correspondent IPROTO_SUBSCRIBE request. Subscription daemon tracks each applier's state and get a list of UUID from \_cluster table. After that we can assign all ids to connected appliers in following manner: first all UUIDs to applier that has equal applier.uuid, rest (orphan) to last peer.
4. Rebalancing. Connect/disconnect should trigger daemon to start reassigning process.
 - On disconnect first get a list of all UUIDs, then iterate through appliers to find orphan and call assigning procedure which should reassigned these UUIDs to last peer, and call resubscribe for it.
 - On connect (back after shoot down), iterate through a list of appliers to build a map of correspondent UUIDs, find stolen one, reassign them to correct one (or just remove from a list), issuing IPROTO_SUBSCRIBE for just connected applier and the one from which we stall these UUIDs back. **TODO**: maintain actual list of UUIDs in appliers (extend applier structure to keep a list of UUIDs).

## Rationale and alternatives

Here existing alternatives are described, and why they appeared to be worse than an implemented thing.
