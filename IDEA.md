# AI Harness

## Background

I'm a Software Developer with 20+ years of experience. I've started using AI, specifically Claude Code, and I find it very useful, but there are issues.
There's _a lot_ of output to read through, and if I give it free reign to perform a bunch of tasks, I lose the ability to keep track of what it's doing. There have been many times I'd interject and make a suggestion of change of course, but it's impossible when the output is so fast.

The alternative is hitting "yes" to _every action_ that Claude wants to perform. Which is a terrible experience for me.

Also, skill atrophy of course.

There's definitely a better way...

## Idea

So my idea is to get back into the IDE (for me it's NeoVim) and not sit in the terminal reading huge walls of output and feeling fully disconnected from the actual proposed and implemented solution(s).

The early days of "AI" was Copilot. It was like smart autocomplete, giving you useful suggestions as you typed, reading your comments and providing solutions, spitting out boilerplate etc. It was really quite useful as in some ways it really felt like a "copilot".

I'd like to get back to this, but with some improvements.

## Proposed Workflow

The way I'd like to work is to have an "agent" or whatever, sitting in my IDE with me as a virtual pair programmer/colleague.

When I start NeoVim, it reads some specific files like `README.md`, `PLAN.md`, for information and background on the current task(s).
This provides some "context".

It will add to this context based on the file(s) I have open (and maybe any files they depend on).

The workflow is I'd like to sit with the problem, think about it, but be able to pop open an agent "chat" panel and discuss my thoughts and have feedback (NOT ACTION) to help me gain a better understanding of the problem and some potential solutions.
This chat will likely need it's own history (or tree of histories) that it can access for greater understanding. Perhaps sections of the tree can be truncated/summerized when accessed (not a destructive action) to reduce it's size.

Then when I feel like I have an idea of what to start with, I'll likely create the files, structs, interfaces etc and start working.
During this stage, I'd like the original Copilot kind of help. I'd like to write comments in the code for my plan like below, and the AI could provide some small (how long is a piece of string I guess) suggestions inline which I'd be able to accept/reject/ignore.

This will likely be some kind of secondary, smaller/faster model as it shouldn't need as much context...maybe.

I don't have a fully clear idea of what this will be like yet, but I feel like being in the editor, with a pair programmer style AI would be a great experience.

The AI could periodically popup a chat message (same panel as earlier) with guidance which I'm able to accept/reject/ignore as I would in real life.

The workflow will end up being an iterative learning and evolving solution with a human (me) and an AI doing pair programming.

There's likely more I'll come up with, but this is the basic idea.

## Software

So this project is going to be my own version of something like Pi, but it sits in the IDE with you as a virtual pair programmer.

You'd hook up your AI, for me it'll be an endpoint to my local LM Studio running models so selecting various "sizes" of models for the agent chat and inline etc.
