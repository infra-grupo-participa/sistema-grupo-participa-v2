export const ATM_TEST_NOTICE_USER_ID = '81d2eaee-cce1-4058-8714-439b0fc6f970';

export function deveExibirAvisoTesteAtm(userId: string | null | undefined): boolean {
  return userId === ATM_TEST_NOTICE_USER_ID;
}
