# Replicaset master promotion

* **Status**: In progress
* **Start date**: 02-03-2018
* **Authors**: Vladislav Shpilevoy @Gerold103 \<v.shpilevoy@tarantool.org\>,
Konstantin Osipov @kostja \<kostja@tarantool.org\>
* **Issues**: [#3055](https://github.com/tarantool/tarantool/issues/3055),
[#2625](https://github.com/tarantool/tarantool/issues/2625)

## Summary

Replicaset master promotion is a procedure of atomic making one slave be new
master, and an old master be slave in a fullmesh master-slave replicaset. Master
is a replica in read-write mode. Slave is a replica in read-only mode.

Master promotion has API:
```Lua
--
-- Called on a slave promotes its role to master, demoting an old
-- one to slave. Called on a master returns an error.
-- @param opts Options.
--        * timeout - the time in which a promotion must be
--          finished;
--        * quorum - before an old master demotion its data must
--          be synced with no less than quorum slave count,
--          including the being promoted one;
--        * force - in any case make the current slave be master
--          even if an old one is unavailable, or quorum is not
--          satisfied, or another promotion is detected.
--
-- @retval true Promotion is started.
-- @retval nil, error Can not start promotion.
--
box.ctl.promote(opts)

--
-- Status of the latest finished or the currently working
-- promotion round.
-- @retval nil Promote() was not called since the instance has
--         been started, or it was started on another instance,
--         that could not sent promotion info to the current
--         instance.
-- @retval status A table with the format:
--    {
--         round_uuid = <Promotion round UUID, generated on
--                       initiator side>,
--         promote_uuid = <UUID of the promotion initiator>,
--         demote_uuid = <UUID of the old master>,
--         state = <Human readable status of the algorithm - it
--                  can be finished ok, finished with an error,
--                  not finished being on one of algorithm steps>,
--         step_number = <Promotion round step identifier>,
--         error = <If the promotion is finished with an error,
--                  then here the error object is stored>,
--         is_finished = <True, if the promotion round is
--                        finished>,
--         start_ts = <Time of the promotion start on initiator
--                     clock>,
--         update_ts = <Time of the last update of this promotion
--                      round by last sender clock>,
--         end_ts = <Time of the promotion finish on initiator
--                   clock, if it is finished>,
--         timeout = <Timeout of the promotion round>,
--         quorum = <Requested quorum>,
--    }
--
box.ctl.promotion_status()

--
-- Try to cancel the promotion.
-- @retval true The promotion is canceled ok.
-- @retval nil, error The promotion was not canceled.
--
box.ctl.promotion_cancel()

--
-- Remove info about all promotions from the entire cluster. It
-- can be useful, when it is necessary to use a role specified in
-- box.cfg{} even if it contradicts with a promotion result.
--
box.ctl.promotion_reset()
```

## Background and motivation

The promote procedure strongly simplifies life of developers since they must not
do all of the promotion steps manually, that in a common case is not a trivial
task, as you can see in the algorithm description in the next section.

The common algorithm, disregarding failures and their processing consists of the
following steps: 
1. On an old master stop accepting DDL/DML - only DQL;
2. Wait until all master data is received by needed slave count, including the
new master candidate;
3. Make the old master be slave;
4. Make the slave be new master;
5. Notify all other slaves, that master is changed.

All of the steps are persisted in WAL, that guarantees, that even after a
promotion participant is restarted, after waking up it will not forgot about
promotion. Persistency eliminates any possibility of making the cluster have two
masters after the promotion.

## Detailed design

Each cluster member has a special system space to distribute promotion steps
over the cluster - `_promotion`:
```Lua
format = {}
-- UUID of the promotion round, generated on an initiator.
format[1] = {'round_uuid', 'string'}
-- UUID of the sender instance.
format[2] = {'source_uuid', 'string'}
-- Increasing step identifier. It grows from 1 to the last one
-- during promotion progress.
format[3] = {'step_number', 'unsigned'}
-- Timestamp, set by a sender using its own clock.
format[4] = {'ts', 'unsigned'}
--
-- Type is what the sender want to get or send. Value depends on
-- type.
-- 'begin'   - the first message that an initiator sends. Value
--             contains all of the info, described in
--             box.ctl.promotion_status() as a map.
--
-- 'status'  - the message, sent by all of the cluster memebers on
--             'begin'. Value is either {role = 'master'} or
--             {role = 'slave'}.
--
-- 'sync'    - the message, that triggers an old master to enter
--             read-only mode and sync with slaves. Value is nil.
--
-- 'success' - the next to last message, sent by an old master
--             when sync was ok. After this the old master is
--             demoted with no timeout. Value is nil.
--
-- 'error'   - an error, that can be send by any cluster member.
--             For example, it can be failed sync, or an existing
--             promotion is found. Value is the error description.
--
-- 'commit'  - the message sent by an initiator, when the
--             'success' status is replicated over quorum
--             replicas. Value is nil.
--
format[5] = {'type', 'string'}
format[6] = {'value', 'any', is_nullable = true}

s = box.schema.create_space('_promotion', {format = format})
```
To participate in a promotion a cluster member just writes into `_promotion`
space and waits until the record is replicated. This space is cleared by a
garbage collector from finished promotions - it is ones with error or commited
status. Only latest promotion is not deleted to be able to restore role after
recovery.

Below the protocol is described. On the image the state machine is showed:
![alt text](https://raw.githubusercontent.com/tarantool/tarantool/gh-3055-box-ctl-promote-rfc/doc/rfc/3055-box_ctl_promote_img1.svg?sanitize=true)

In the simplest case the being promoted instance is master already - immediately
finish promotion with the error and with no persisting that. Now assume
promote() is called on a slave. At first, the initiator broadcasts initial
promotion status: `promote_uuid, step_number, start_ts, timeout, round_uuid,
...`.

Each cluster member, received the promotion status, checks if it already knows
about another active promotions. If has, then responds error to the newer
promotion request. Else it broadcasts its status that consists of role.

Initiator collects responses from `_promotion` space. If an active promotion
error is found, then stop the promotion - it is failed. Now assume active
promotions are not found. The space `_promotion` looks like this:
```YAML
---
- - ['<round_uuid>', '<init_uuid>', 0, <ts1>, 'begin', <status map>]
  - ['<round_uuid>', '<slave1_uuid>', 0, <ts2>, 'status', {role = slave}]
  - ['<round_uuid>', '<slave2_uuid>', 0, <ts3>, 'status', {role = slave}]
  ...
  - ['<round_uuid>', '<master_uuid>', 0, <ts4>, 'status', {role = master}]
...
```

Consider role responses:
* multiple masters are found;
* a master is not found;
* single master is found.

### Multiple masters are found

Immediately abort the promotion - promote must not destroy master-master
replication. Broadcast this fact.

### Master is not found

It is possible in two cases: the cluster is read-only and actually does not have
a master; a master is unavailable for the promotion initiator. These two cases
can be controlled by quorum - if it is necessary to demote an old master and it
is known to be active, the quorum must be equal to the cluster size. Consider
the algorithm steps, when a master is not found.

1. Initiator broadcasts sync request and waits timeout for sync with at least
quorum replicas. On timeout broadcast `error` status.

2. On success sync the initiator broadcasts the `success` status and enters
master role. Else broadcast error status. When `success` is replicated over the
quorum, the initiator broadcasts `commit`.

The reason why the promotion must work with not found old master is that a user
on failed promotion that left the cluster in read-only state must be able to
return a master.

### Single master is found

It is possible in two cases as well: the cluster actually has a single master,
or another master is unavailable. Necessity to ignore possibility of unavailable
masters existence can be controlled by quorum. Consider the algorithm steps.

1. Broadcast `sync` request. The old master interprets it as the demotion
request. On demote the old master enters read-only mode on the at most current
promotion round duration, and waits timeout for sync with quorum replicas
including the requester. If the `sync` was ok, the `success` is broadcasted and
the old master finishes its demotion becoming a slave. Else the `error` is
broadcasted.

2. The initiator receives sync result via waiting for new data in space
`_promote`. If time is out, then just broadcast the `error` and finish. If sync
result is received and it is failed, then the promotion is aborted already by
this `error`. Assume the sync was ok. The initiator received `success` becomes a
new master, entering the read-write mode. According to this schema, it is
possible, that `error` can be written after `success`, if the old master
broadcasted `success`, but it was replicated to the initiator too long. In such
a case when this `error` reaches the old master, it must try to return to the
master role. For this he checks if there no more promotions were runned, and
just becomes a master back.

3. After the `success` is broadcasted over quorum replicas, the initiator writes
`commit` into `_promotion` space.

### Promotion canceling

Promotion cancel can be run from an old master and from an initiator. It just
broadcasts `error` status via `_promotion` space, if an active promotion is
found, and it is not already `success`, `error` or `commit`.

### Recovery

Recovery procedure consists of several independent cases, if a `_promotion`
space is not empty:
* Recovery of non-participant slave replica. Just do nothing.
* Recovery of non-participant master replica. Ignore 'master' role - another
master exists already.
* Recovery of the old master.

	Assume the found promotion state is `begin` or `status` or `sync` -
	broadcast an `error` and become a master.

	Assume the state is `error` - then the promotion is failed, and the
	current replica is still a master.

	Assume the `success` is found. Then the replica can not decide what to
	do with no the promotion initiator. Indeed, it is possible, that the
	initiator already became a new master, and broadcasted `commit`, that
	just did not manage to reach the current replica. Even timeout can not
	be used here, because the replica can be separated from a new master due
	to network problems. So it becomes slave until a promotion result is got
	from the initiator.

	Assume the `commit` is found - then become a slave regardless of
	configuration.

* Recovery of the promotion initiator.

	Assume the found promotion state is `begin` or `status` or `sync` -
	broadcast an `error` and become a slave.

	Assume the state is `error` - then become a slave regardless of
	configuration.

	Assume the status is `success` or `commit` - then become a master
	regardless of configuration. If the status is `success` that is
	replicated over quorum then broadcast `commit`.
