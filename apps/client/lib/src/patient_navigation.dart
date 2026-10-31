/// Legacy branch/domain identities stay stable. Only the four visible menu
/// destinations change; booking, tickets and agenda remain routable internally.
const patientBranchTabs = [0, 2, 1, 3, 5, 6];
const patientBottomTabs = [0, 2, 6, 5];
const patientBottomBranches = [0, 1, 5, 4];

int patientBottomIndex(int tab) => switch (tab) {
  0 => 0,
  1 || 2 || 3 || 4 => 1,
  6 => 2,
  5 => 3,
  _ => 0,
};
