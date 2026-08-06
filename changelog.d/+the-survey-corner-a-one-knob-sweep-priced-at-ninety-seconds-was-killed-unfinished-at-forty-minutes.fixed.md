`limb_ceiling` and `spawns` are in series - `spawns × limb_ceiling` is the birth
budget - and each was swept with the other held. So both comments quote the
cheaper fuse's cost curve, and both understate the joint corner by an order of
magnitude.

Go's survey, timed per corner: 256 limbs is 1.1 s at any churn from 4096 to
262144; 1024 limbs is 3.4 s at churn 1024 and **99.5 s** at churn 65536; 4096
limbs is 251.6 s at churn 4096, and at churn 65536 it was **killed unfinished
at forty minutes**. `limb_ceiling` recorded that corner as "a second into
ninety".

Every one of those corners reports the identical survey - worst p99 rank 18, one
residue, 4 of 8 chains held, 4 refused - so the whole curve is cost with no
answer behind it. This is `crowd`/`skeins`' defect with the sign flipped: there
a one-knob sweep hid a benefit, here it hides a 90x cost, and a project whose
tooling must not tax the machine cares about the second one at least as much.

Both numbers stay. `spawns = 16` is now right for a second reason: the corner it
keeps the survey out of is 90x, not 5x. `fan_ceiling` is a third axis and is not
in series with either - 256 costs 3x and moves worst rank 18 → 43 whatever the
other two are set to, the only one of the three that changes the survey at all,
and it changes it for the worse.
