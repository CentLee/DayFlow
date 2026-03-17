# DayFlow Review Checklist

Every PR must be reviewed with this checklist.

## Product Alignment

- does the change conflict with `docs/product-spec.md`?
- does it change budget behavior without updating product docs?
- does it exceed MVP scope?

## Contract Alignment

- does the change drift from `docs/api-contract.md`?
- does the iOS state model still match the payload shape?
- is sync behavior still consistent with `docs/sync-model.md`?

## Data Boundary Safety

- does any calendar sharing path leak budget data?
- are user-scoped resources still protected by owner checks?
- are invite/session rules enforced?

## Simplicity

- is the solution larger than the issue requires?
- did the change introduce unnecessary abstractions?
- could the same behavior be delivered with fewer moving parts?

## Testing

- were behavior-changing code paths tested?
- are failure paths covered?
- is any missing test explicitly called out?

## Required Review Output

- findings ordered by severity
- open questions or assumptions
- residual risks
