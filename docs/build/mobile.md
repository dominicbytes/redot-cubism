# Android and iOS status

Android and iOS are experimental, later-stage targets in the implementation
plan. The current port has no qualified mobile build or exported application.
Retained upstream platform branches are not tested mobile support.

Mobile work requires separately verified SDK/Core architectures, Redot bindings
and export templates, application lifecycle behavior, renderer limits, memory
budgets and packaging on actual devices. iOS signing and Android packaging must
be validated in their target toolchains. Desktop tests cannot establish these
results. Use the [desktop setup](../quick-start.md) for the current development
path; do not treat its library names or export procedure as a mobile recipe.
