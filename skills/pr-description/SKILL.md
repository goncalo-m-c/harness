---
name: pr-description
description: Write a pull request body in three sections (What is changing, Why, Extras). Use when opening a PR or rewriting its description.
---

# PR description

Write the body from the intent: the spec's proposal and the ticket. Use the diff to check every claim.
Write short, plain sentences.

Use exactly these three sections, in this order. Add more only when the user asks.

## What is changing

The behaviour after the merge, in a few sentences.
Say what a user or a caller will notice. Name files only when the change is about them.

## Why

The problem, and why it matters now. Link the ticket.

## Extras

Bullets for what the diff does not show:
- caveats and known limits
- follow-up work
- a design pattern the change introduces, named, with the reason
- manual steps after the merge
- links

Write `None.` when there is nothing to add.

## Done when

The three headings appear in order, each section has content, and every claim matches the diff.
