# MIGRATION.md - Moving off Voltage onto this node

You cannot move open Lightning channels between hosts. Voltage only lets you export
your seed + a Static Channel Backup (SCB), and restoring an SCB CLOSES channels
(it's recovery, not migration). So the clean path is: close on Voltage, move the
on-chain funds, reopen here.

## Steps

1. **Set up this node first** (README Phases 1-3) and let it fully sync, so it's
   ready to receive before you move anything.
2. **Record your channels** in Voltage's ThunderHub (peers you want to reconnect to).
3. **Wait for low on-chain fees** (check mempool.space). You pay to close AND to
   reopen.
4. **Cooperatively close all channels on Voltage** (via ThunderHub), while peers are
   online - cheaper and faster than force closes, funds available immediately.
5. **Withdraw all on-chain funds** from Voltage to an address on THIS node. Wait for
   confirmations.
6. **Open new channels** from this node to the peers you noted (batch-open to save
   fees).
7. **Test send + receive**, then cancel Voltage. Never cancel before funds have
   confirmed here.

## Cautions
- Never run the same seed on two live nodes at once. Easiest: fresh seed here.
  (Keeping the same node pubkey is possible by initializing with the Voltage seed,
  but only after Voltage is fully shut down - and channels close either way.)
- You will rebuild INBOUND liquidity - new channels start empty on the receive side.
- Keep the Voltage seed + SCB safe until the move is done, as an emergency fallback.

## LNbits data (restoring your wallets)
LNbits "wallets" are entries in LNbits' database (IDs, API keys, balances) - NOT
key-holding wallets. To restore them, you need Voltage to let you EXPORT the LNbits
data folder (the .sqlite3 files) or a database dump.
- Ask Voltage support: "Can I export my LNbits data folder / database?"
- If YES: copy it into the LNbits volume (/app/data) on this deployment, point LNbits
  at THIS node, start it -> wallets + API keys + balances come back (apps keep
  working, same keys).
- If NO: before shutting Voltage down, record each wallet's ID + API keys, recreate
  the wallets here, and update any app that used the old keys.
- Either way: LNbits balances are just numbers backed by node liquidity. Make sure
  THIS node holds at least the total of all LNbits balances after migration.
