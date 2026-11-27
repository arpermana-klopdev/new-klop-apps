import { useState, type FormEvent } from "react";
import { Button, Field, TextInput } from "../../components/ui";

export type PersonalIdentityValues = {
  phoneNumber: string;
  countryCode: string;
  region: string;
  city: string;
  postalCode: string;
  addressLine: string;
};

type PersonalIdentityFormProps = {
  initialValues?: Partial<PersonalIdentityValues>;
  onSubmit: (values: PersonalIdentityValues) => void;
  submitting?: boolean;
  submitLabel?: string;
};

const emptyValues: PersonalIdentityValues = {
  phoneNumber: "",
  countryCode: "",
  region: "",
  city: "",
  postalCode: "",
  addressLine: "",
};

export function PersonalIdentityForm({
  initialValues,
  onSubmit,
  submitting = false,
  submitLabel = "Save personal details",
}: PersonalIdentityFormProps) {
  const [values, setValues] = useState<PersonalIdentityValues>({
    ...emptyValues,
    ...initialValues,
  });

  function update(field: keyof PersonalIdentityValues, value: string) {
    setValues((current) => ({ ...current, [field]: value }));
  }

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    onSubmit(values);
  }

  return (
    <section aria-labelledby="personal-identity-form-heading" className="rounded-2xl border border-slate-200 bg-white p-5 shadow-soft dark:border-slate-800 dark:bg-slate-900 sm:p-6">
      <div className="mb-5">
        <h2 id="personal-identity-form-heading" className="text-base font-bold">Personal identity details</h2>
        <p className="mt-1 text-xs text-slate-500">Contact and address information for a personal profile.</p>
      </div>
      <form className="space-y-4" onSubmit={submit}>
        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="Phone number" htmlFor="personal-phone">
            <TextInput id="personal-phone" autoComplete="tel" value={values.phoneNumber} onChange={(event) => update("phoneNumber", event.target.value)} />
          </Field>
          <Field label="Country code" htmlFor="personal-country-code">
            <TextInput id="personal-country-code" autoComplete="country" value={values.countryCode} onChange={(event) => update("countryCode", event.target.value)} />
          </Field>
          <Field label="Region" htmlFor="personal-region">
            <TextInput id="personal-region" autoComplete="address-level1" value={values.region} onChange={(event) => update("region", event.target.value)} />
          </Field>
          <Field label="City" htmlFor="personal-city">
            <TextInput id="personal-city" autoComplete="address-level2" value={values.city} onChange={(event) => update("city", event.target.value)} />
          </Field>
          <Field label="Postal code" htmlFor="personal-postal-code">
            <TextInput id="personal-postal-code" autoComplete="postal-code" value={values.postalCode} onChange={(event) => update("postalCode", event.target.value)} />
          </Field>
          <Field label="Address" htmlFor="personal-address">
            <TextInput id="personal-address" autoComplete="street-address" value={values.addressLine} onChange={(event) => update("addressLine", event.target.value)} />
          </Field>
        </div>
        <div className="flex justify-end">
          <Button type="submit" disabled={submitting}>{submitting ? "Saving…" : submitLabel}</Button>
        </div>
      </form>
    </section>
  );
}
