import { expect, test } from "@playwright/test";

test("login form reports a safe backend authentication error", async ({ page }) => {
  await page.route("**/auth/login", async (route) => {
    await route.fulfill({
      status: 401,
      contentType: "application/problem+json",
      body: JSON.stringify({
        title: "INVALID_CREDENTIALS",
        status: 401,
        detail: "Email or password is incorrect.",
        success: false,
        error: { code: "INVALID_CREDENTIALS", message: "Email or password is incorrect." },
        meta: { requestId: "browser-test" },
      }),
    });
  });

  await page.goto("/login");
  await page.getByLabel("Email address").fill("person@example.com");
  await page.getByLabel("Password", { exact: true }).fill("incorrect-password");
  await page.getByRole("button", { name: "Sign in" }).click();

  await expect(page.getByRole("alert")).toContainText(
    "Email or password is incorrect.",
  );
  await expect(page).toHaveURL(/\/login$/);
});

test("login branding remains visible without horizontal overflow on mobile", async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 812 });
  await page.goto("/login");

  await expect(page).toHaveTitle("KLOP Next – One Portal");
  await expect(page.getByAltText("KLOP Next – One Portal")).toBeVisible();
  await expect(page.getByRole("link", { name: "Create an account" })).toBeVisible();
  await expect(page.getByText(/continue with google/i)).toHaveCount(0);
  await expect(page.getByText(/continue with sso/i)).toHaveCount(0);
  await expect(page.getByText(/or continue with/i)).toHaveCount(0);
  const signInButton = page.getByRole("button", { name: "Sign in" });
  const createAccountButton = page.getByRole("link", { name: "Create an account" });
  const signInBox = await signInButton.boundingBox();
  const createAccountBox = await createAccountButton.boundingBox();
  if (!signInBox || !createAccountBox) throw new Error("Auth buttons must be measurable.");
  expect(createAccountBox.width).toBe(signInBox.width);
  expect(createAccountBox.height).toBe(signInBox.height);
  const [signInBackground, createAccountBackground] = await Promise.all([
    signInButton.evaluate((element) => getComputedStyle(element).backgroundColor),
    createAccountButton.evaluate((element) => getComputedStyle(element).backgroundColor),
  ]);
  expect(createAccountBackground).not.toBe(signInBackground);
  const documentWidth = await page.evaluate(() => document.documentElement.scrollWidth);
  expect(documentWidth).toBeLessThanOrEqual(375);
});

test("self-registration keeps the existing Full Name, Email, and Password fields", async ({ page }) => {
  await page.goto("/login");
  await page.getByRole("link", { name: "Create an account" }).click();

  await expect(page).toHaveURL(/\/register$/);
  await expect(page.getByRole("heading", { name: "Create your KLOP account" })).toBeVisible();
  await page.getByRole("link", { name: "Back to sign in" }).click();
  await expect(page).toHaveURL(/\/login$/);
  await page.getByRole("link", { name: "Create an account" }).click();
  await page.getByRole("button", { name: /PERSONAL/ }).click();
  await page.getByRole("button", { name: "Continue" }).click();
  await expect(page.getByRole("textbox", { name: "Full Name" })).toBeVisible();
  await expect(page.getByRole("textbox", { name: "Email Address" })).toBeVisible();
  await expect(page.getByLabel("Password", { exact: true })).toBeVisible();
  await expect(page.getByLabel("Confirm Password")).toBeVisible();
  await expect(page.locator(".auth-form-icon")).toHaveCount(0);
  await expect(page.locator(".auth-input-icon.lucide-mail")).toHaveCount(1);
  await expect(page.getByRole("link", { name: "Sign in" })).toBeVisible();
  const signInFollowsCreate = await page.evaluate(() => {
    const createButton = document.querySelector('button[type="submit"]');
    const signInPrompt = document.querySelector(".auth-register-signin");
    return Boolean(
      createButton &&
        signInPrompt &&
        createButton.compareDocumentPosition(signInPrompt) & Node.DOCUMENT_POSITION_FOLLOWING,
    );
  });
  expect(signInFollowsCreate).toBe(true);
  await expect(page.getByText("Enter your full name.")).toHaveCount(0);
  await expect(page.getByText("Enter a valid email address.")).toHaveCount(0);
  const termsSectionStyle = await page.locator(".auth-terms-section").evaluate((element) => {
    const style = getComputedStyle(element);
    return { borderTopWidth: style.borderTopWidth, paddingTop: style.paddingTop };
  });
  expect(termsSectionStyle).toEqual({ borderTopWidth: "0px", paddingTop: "0px" });
});

test("registration stays blocked while the ORGANIZATION Terms PDF is a draft", async ({ page }) => {
  test.setTimeout(90_000);
  let registerCalled = false;
  await page.route("**/auth/register", async (route) => {
    registerCalled = true;
    await route.fulfill({
      status: 202,
      contentType: "application/json",
      body: JSON.stringify({
        success: true,
        data: { message: "Accepted." },
        error: null,
        meta: { requestId: "browser-test" },
      }),
    });
  });

  await page.goto("/register");
  await page.getByRole("button", { name: /ORGANIZATION/ }).click();
  await page.getByRole("button", { name: "Continue" }).click();
  await page.getByLabel("Full Name").fill("Ada Lovelace");
  await page.getByLabel("Email Address").fill("ada@example.com");
  await page.getByLabel("Password", { exact: true }).fill("existing-password-policy");
  await page.getByLabel("Confirm Password").fill("existing-password-policy");
  await expect(page.getByRole("button", { name: "Create account" })).toBeDisabled();

  await page.getByRole("button", { name: "Read the ORGANIZATION Terms & Conditions" }).click();
  const dialog = page.getByRole("dialog");
  await expect(dialog).toBeVisible();
  await expect(dialog).toContainText("Terms & Conditions Draft");
  await expect(dialog).toContainText("This document is a draft and cannot be accepted for registration.");
  const viewer = dialog.getByRole("region", { name: /Terms & Conditions Draft.*PDF pages/ });
  await expect(viewer.getByRole("status")).toContainText("All 6 pages are ready to review.", {
    timeout: 45_000,
  });
  await expect(viewer.locator("canvas.auth-terms-pdf-page")).toHaveCount(6, {
    timeout: 45_000,
  });
  await expect(dialog.getByRole("checkbox")).toBeDisabled();
  await expect(dialog.getByRole("button", { name: "I Agree" })).toBeDisabled();
  await expect(page).toHaveURL(/\/register$/);

  const pdfUrl = new URL("/documents/KLOP_Next_Terms_and_Conditions.pdf", page.url()).toString();
  const pdfResponse = await page.request.get(pdfUrl);
  expect(pdfResponse.ok()).toBe(true);
  expect(pdfResponse.headers()["content-type"]).toContain("application/pdf");

  const header = dialog.getByRole("heading", {
    name: /Terms & Conditions Draft/,
  });
  const footer = dialog.locator(".auth-terms-modal-footer");
  const bodyScrollBefore = await page.evaluate(() => window.scrollY);
  const viewerDimensions = await viewer.evaluate((element) => ({
    clientHeight: element.clientHeight,
    scrollHeight: element.scrollHeight,
  }));
  expect(viewerDimensions.scrollHeight).toBeGreaterThan(viewerDimensions.clientHeight);
  const headerBeforeScroll = await header.boundingBox();
  const footerBeforeScroll = await footer.boundingBox();
  if (!headerBeforeScroll || !footerBeforeScroll) {
    throw new Error("Terms modal header and footer must be measurable.");
  }
  await viewer.hover();
  await page.mouse.wheel(0, 900);
  await expect.poll(() => viewer.evaluate((element) => element.scrollTop)).toBeGreaterThan(0);
  expect(await page.evaluate(() => window.scrollY)).toBe(bodyScrollBefore);
  const [headerAfterScroll, footerAfterScroll] = await Promise.all([
    header.boundingBox(),
    footer.boundingBox(),
  ]);
  expect(headerAfterScroll?.y).toBe(headerBeforeScroll.y);
  expect(footerAfterScroll?.y).toBe(footerBeforeScroll.y);
  await expect(dialog.getByRole("button", { name: "Cancel" })).toBeInViewport();

  await dialog.getByRole("button", { name: "Cancel" }).click();
  await expect(dialog).not.toBeVisible();
  await expect(page.getByLabel("Full Name")).toHaveValue("Ada Lovelace");
  await expect(page.getByLabel("Email Address")).toHaveValue("ada@example.com");
  await expect(page.getByLabel("Password", { exact: true })).toHaveValue("existing-password-policy");
  await expect(page.getByLabel("Confirm Password")).toHaveValue("existing-password-policy");
  await expect(page.getByRole("status", { name: "ORGANIZATION Terms not accepted" })).toBeVisible();
  await expect(page.getByRole("button", { name: "Create account" })).toBeDisabled();
  expect(registerCalled).toBe(false);
});

test("PERSONAL registration opens the combined Terms PDF without approving the draft", async ({ page }) => {
  test.setTimeout(90_000);
  await page.goto("/register");
  await page.getByRole("button", { name: /PERSONAL/ }).click();
  await page.getByRole("button", { name: "Continue" }).click();
  await page.getByRole("button", { name: "Read the PERSONAL Terms & Conditions" }).click();

  const dialog = page.getByRole("dialog");
  await expect(dialog).toBeVisible();
  await expect(dialog).toContainText("PERSONAL registration");
  await expect(dialog).toContainText("PERSONAL dan ORGANIZATION");
  await expect(dialog).toContainText("This document is a draft and cannot be accepted for registration.");
  await expect(dialog.getByRole("region", { name: /Terms & Conditions Draft.*PDF pages/ })
    .locator("canvas.auth-terms-pdf-page")).toHaveCount(6, { timeout: 45_000 });
  await expect(page).toHaveURL(/\/register$/);
  await expect(dialog.getByRole("checkbox")).toBeDisabled();
  await dialog.getByRole("button", { name: "Cancel" }).click();
  await expect(dialog).not.toBeVisible();
  await expect(page.getByRole("button", { name: "Create account" })).toBeDisabled();
});

test("Terms PDF load failure keeps acceptance unavailable", async ({ page }) => {
  await page.route("**/documents/KLOP_Next_Terms_and_Conditions.pdf", async (route) => {
    await route.fulfill({ status: 404, contentType: "application/pdf", body: "" });
  });
  await page.goto("/register");
  await page.getByRole("button", { name: /ORGANIZATION/ }).click();
  await page.getByRole("button", { name: "Continue" }).click();
  await page.getByRole("button", { name: "Read the ORGANIZATION Terms & Conditions" }).click();

  const dialog = page.getByRole("dialog");
  await expect(dialog).toBeVisible();
  await expect(dialog.getByRole("alert")).toContainText("We couldn't load the Terms.");
  await expect(dialog.getByRole("checkbox")).toBeDisabled();
  await expect(dialog.getByRole("button", { name: "I Agree" })).toBeDisabled();
});

test("Terms modal is keyboard accessible and fits a mobile viewport", async ({ page }) => {
  test.setTimeout(90_000);
  await page.setViewportSize({ width: 375, height: 812 });
  await page.goto("/register");
  await page.getByRole("button", { name: /PERSONAL/ }).click();
  await page.getByRole("button", { name: "Continue" }).click();

  const termsButton = page.getByRole("button", { name: "Read the PERSONAL Terms & Conditions" });
  await termsButton.focus();
  await page.keyboard.press("Enter");
  const dialog = page.getByRole("dialog");
  await expect(dialog).toBeVisible();
  const viewer = dialog.getByRole("region", { name: /Terms & Conditions Draft.*PDF pages/ });
  await expect(viewer.locator("canvas.auth-terms-pdf-page")).toHaveCount(6, {
    timeout: 45_000,
  });
  const bounds = await dialog.boundingBox();
  if (!bounds) throw new Error("Terms dialog must be visible and measurable.");
  expect(bounds.x).toBeGreaterThanOrEqual(0);
  expect(bounds.x + bounds.width).toBeLessThanOrEqual(375);
  for (let index = 0; index < 6; index += 1) {
    await page.keyboard.press("Tab");
  }
  const focusIsTrapped = await dialog.evaluate((element) =>
    element.contains(document.activeElement),
  );
  expect(focusIsTrapped).toBe(true);
  await page.keyboard.press("Escape");
  await expect(dialog).not.toBeVisible();
  await expect(termsButton).toBeFocused();
  const documentWidth = await page.evaluate(() => document.documentElement.scrollWidth);
  expect(documentWidth).toBeLessThanOrEqual(375);
});
