// Products: what the shop sells at checkout, and shows clients in the Izzy Clipz app. Add
// and edit (name, description, a price or "no price", shown in the app or not), a photo as
// the server takes it (a JPEG, made in the browser from whatever photo is picked), and
// delete, which asks first. Past sales keep a deleted product's name.

import { useRef, useState, type FormEvent } from 'react';
import { errorMessage } from '../../api/errors';
import { Dialog } from '../../components/Dialog';
import { Icon } from '../../components/Icon';
import { ownerApi } from '../api/client';
import { ErrorBanner, PageHeader, ProductPlaceholder, SidePanel, SkeletonCard, SuccessLine } from '../components/common';
import { demo, useBusinessTitle, useLoad } from '../hooks';
import { editableMoney, moneyWithCommas, parseMoney } from '../lib/money';
import { PhotoProblem, photoAsJpeg } from '../lib/photo';
import type { Product, ProductInput } from '../types';

interface Draft {
  name: string;
  description: string;
  priceText: string;
  noPrice: boolean;
  visible: boolean;
}

function draftOf(product: Product | null): Draft {
  return {
    name: product?.name ?? '',
    description: product?.description ?? '',
    priceText: product?.priceCents != null ? editableMoney(product.priceCents) : '',
    noPrice: product !== null && product.priceCents === null,
    visible: product?.visible ?? true,
  };
}

type Field = 'name' | 'description' | 'price';

/** What's wrong with the product as typed, and in which field, or null. */
export function productProblem(draft: Draft): { field: Field; message: string } | null {
  if (draft.name.trim() === '') return { field: 'name', message: 'Give the product a name.' };
  if ([...draft.name.trim()].length > 80) return { field: 'name', message: 'Keep the name to 80 characters or fewer.' };
  if ([...draft.description.trim()].length > 500) return { field: 'description', message: 'Keep the description to 500 characters or fewer.' };
  if (!draft.noPrice) {
    const cents = parseMoney(draft.priceText);
    if (cents === null) return { field: 'price', message: 'Type the price, like 18 or 17.50. Or tick "No price" to type it at checkout.' };
    if (cents > 1_000_000) return { field: 'price', message: 'That price is too high.' };
  }
  return null;
}

/** A field's own error, under it: what to fix there. */
function FieldError({ id, message }: { id: string; message: string }) {
  return (
    <p className="field__error" id={id} role="alert">
      <Icon name="error" />
      <span>{message}</span>
    </p>
  );
}

function inputOf(draft: Draft): ProductInput {
  return {
    name: draft.name.trim(),
    description: draft.description.trim() === '' ? null : draft.description.trim(),
    priceCents: draft.noPrice ? null : parseMoney(draft.priceText),
    visible: draft.visible,
  };
}

function readAsDataUrl(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result));
    reader.onerror = () => reject(new Error('unreadable'));
    reader.readAsDataURL(blob);
  });
}

function Editor({ product, onSaved, onCancel }: { product: Product | null; onSaved: (product: Product, warning?: string) => void; onCancel: () => void }) {
  const [draft, setDraft] = useState<Draft>(() => draftOf(product));
  const [photo, setPhoto] = useState<{ jpeg: Blob; preview: string } | null>(null);
  const [photoError, setPhotoError] = useState<string | null>(null);
  /** What the server said went wrong (shown by the buttons). */
  const [error, setError] = useState<string | null>(null);
  /** What's wrong in a field, shown under it. */
  const [problem, setProblem] = useState<{ field: Field; message: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const fields = { name: useRef<HTMLInputElement>(null), description: useRef<HTMLTextAreaElement>(null), price: useRef<HTMLInputElement>(null) };
  const change = (patch: Partial<Draft>) => {
    setDraft({ ...draft, ...patch });
    setError(null);
    setProblem(null);
  };
  const invalid = (field: Field) =>
    problem?.field === field ? { 'aria-invalid': true as const, 'aria-describedby': `product-${field}-error` } : {};

  const pick = async (file: File | undefined) => {
    setPhotoError(null);
    if (!file) return;
    try {
      // The demo keeps photos in this browser's storage, so it keeps them smaller.
      const jpeg = await photoAsJpeg(file, demo() ? 640 : 1600);
      setPhoto({ jpeg, preview: await readAsDataUrl(jpeg) });
    } catch (caught) {
      setPhotoError(caught instanceof PhotoProblem ? caught.message : "That photo couldn't be opened. Try another one.");
    }
  };

  const save = async (event: FormEvent) => {
    event.preventDefault();
    const wrong = productProblem(draft);
    if (wrong) {
      // Said under the field, which takes the focus (and comes into view on a phone).
      setProblem(wrong);
      fields[wrong.field].current?.focus();
      return;
    }
    setBusy(true);
    setError(null);
    try {
      let saved = product ? await ownerApi.updateProduct(product.id, inputOf(draft)) : await ownerApi.createProduct(inputOf(draft));
      if (photo) {
        try {
          saved = await ownerApi.uploadProductPhoto(saved.id, photo.jpeg);
        } catch (caught) {
          // The product is saved; only the photo didn't go. Edit it to try the photo again.
          onSaved(saved, `${saved.name} is saved, but its photo isn't: ${errorMessage(caught)} Click Edit to try the photo again.`);
          return;
        }
      }
      onSaved(saved);
    } catch (caught) {
      setError(errorMessage(caught));
      setBusy(false);
    }
  };

  const shown = photo?.preview ?? product?.imageUrl ?? null;
  return (
    <form className="biz-editor" onSubmit={(event) => void save(event)} noValidate data-testid="product-editor">
      <div className="biz-editor__photo">
        {shown ? (
          <img src={shown} alt={`Photo of ${draft.name || 'the product'}`} width={160} height={160} />
        ) : (
          <ProductPlaceholder className="biz-product__placeholder biz-editor__placeholder" />
        )}
        <div>
          <label className="button button--secondary biz-file">
            <input type="file" accept="image/*" className="visually-hidden" onChange={(e) => void pick(e.target.files?.[0])} />
            {shown ? 'Choose another photo' : 'Choose a photo'}
          </label>
          <p className="field__hint">A square photo looks best. It's saved as a JPEG.</p>
          {photoError ? (
            <p className="field__error" role="alert">
              <Icon name="error" />
              <span>{photoError}</span>
            </p>
          ) : null}
        </div>
      </div>
      <div className="field">
        <label className="field__label" htmlFor="product-name">
          Name
        </label>
        <input
          ref={fields.name}
          id="product-name"
          className="field__input"
          value={draft.name}
          maxLength={80}
          onChange={(e) => change({ name: e.target.value })}
          {...invalid('name')}
        />
        {problem?.field === 'name' ? <FieldError id="product-name-error" message={problem.message} /> : null}
      </div>
      <div className="field">
        <label className="field__label" htmlFor="product-description">
          Description <span className="field__optional">(optional)</span>
        </label>
        <textarea
          ref={fields.description}
          id="product-description"
          className="field__input"
          value={draft.description}
          maxLength={500}
          rows={3}
          onChange={(e) => change({ description: e.target.value })}
          {...invalid('description')}
        />
        {problem?.field === 'description' ? <FieldError id="product-description-error" message={problem.message} /> : null}
      </div>
      <div className="field">
        <label className="field__label" htmlFor="product-price">
          Price
        </label>
        <div className="biz-money-input">
          <span aria-hidden="true">$</span>
          <input
            ref={fields.price}
            id="product-price"
            className="field__input"
            inputMode="decimal"
            value={draft.noPrice ? '' : draft.priceText}
            disabled={draft.noPrice}
            placeholder={draft.noPrice ? 'No price' : undefined}
            onChange={(e) => change({ priceText: e.target.value })}
            {...invalid('price')}
          />
        </div>
        {problem?.field === 'price' ? <FieldError id="product-price-error" message={problem.message} /> : null}
      </div>
      <label className="checkbox">
        <input type="checkbox" checked={draft.noPrice} onChange={(e) => change({ noPrice: e.target.checked })} />
        <span className="checkbox__text">
          <span className="checkbox__label">No price</span>
          <span className="secondary small">Checkout asks for the price each time it's sold.</span>
        </span>
      </label>
      <label className="checkbox">
        <input type="checkbox" checked={draft.visible} onChange={(e) => change({ visible: e.target.checked })} />
        <span className="checkbox__text">
          <span className="checkbox__label">Show in the Izzy Clipz app</span>
          <span className="secondary small">Off: hidden from clients, but you can still sell it at checkout.</span>
        </span>
      </label>
      {error ? (
        <p className="field__error" role="alert">
          <Icon name="error" />
          <span>{error}</span>
        </p>
      ) : null}
      <div className="biz-editor__actions">
        <button type="button" className="button button--secondary" onClick={onCancel} disabled={busy}>
          Cancel
        </button>
        <button type="submit" className="button button--primary" disabled={busy}>
          {busy ? 'Saving…' : product ? 'Save changes' : 'Add product'}
        </button>
      </div>
    </form>
  );
}

function ProductCard({ product, onEdit, onDelete }: { product: Product; onEdit: () => void; onDelete: () => void }) {
  return (
    <li className="biz-product" data-testid="product">
      {product.imageUrl ? (
        <img className="biz-product__photo" src={product.imageUrl} alt="" width={320} height={240} loading="lazy" />
      ) : (
        <ProductPlaceholder className="biz-product__placeholder" />
      )}
      <div className="biz-product__body">
        <h2 className="biz-product__name">{product.name}</h2>
        <p className="biz-product__price">{product.priceCents === null ? 'No price' : moneyWithCommas(product.priceCents)}</p>
        {product.description ? <p className="biz-product__description">{product.description}</p> : null}
        <p className={`biz-badge ${product.visible ? 'biz-badge--completed' : 'biz-badge--cancelled'} biz-product__visibility`}>
          {product.visible ? 'Shown in the app' : 'Hidden from clients'}
        </p>
        <div className="biz-product__actions">
          <button type="button" className="button button--secondary" onClick={onEdit} aria-label={`Edit ${product.name}`}>
            Edit
          </button>
          <button type="button" className="text-button text-button--danger" onClick={onDelete} aria-label={`Delete ${product.name}`}>
            Delete
          </button>
        </div>
      </div>
    </li>
  );
}

export function ProductsPage() {
  useBusinessTitle('Products', 'The products the shop sells at checkout and shows in the Izzy Clipz app.');
  const list = useLoad<Product[]>('products', (signal) => ownerApi.products(signal));
  const [editing, setEditing] = useState<Product | 'new' | null>(null);
  const [deleting, setDeleting] = useState<Product | null>(null);
  const [busy, setBusy] = useState(false);
  const [deleteError, setDeleteError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [warning, setWarning] = useState<string | null>(null);
  const products = list.data;

  const remove = async () => {
    if (!deleting) return;
    setBusy(true);
    setDeleteError(null);
    try {
      await ownerApi.deleteProduct(deleting.id);
      setMessage(`Deleted ${deleting.name}. Past sales keep its name.`);
      setDeleting(null);
      list.reload();
    } catch (caught) {
      setDeleteError(errorMessage(caught));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="container container--wide biz-page" data-testid="products-page">
      <PageHeader title="Products" lead="What you sell at checkout, and what clients see in the Izzy Clipz app.">
        <button
          type="button"
          className="button button--primary"
          onClick={() => {
            setMessage(null);
            setWarning(null);
            setEditing('new');
          }}
        >
          Add a product
        </button>
      </PageHeader>
      {message ? <SuccessLine testId="products-message">{message}</SuccessLine> : null}
      {warning ? <ErrorBanner message={warning} /> : null}
      {list.status === 'error' ? <ErrorBanner title="Couldn't load the products" message={list.error} onRetry={list.reload} /> : null}
      {products === null ? (
        list.status !== 'error' ? (
          <div className="biz-products">
            <SkeletonCard label="Loading the products…" />
            <SkeletonCard label="Loading the products…" />
          </div>
        ) : null
      ) : products.length === 0 ? (
        <div className="biz-empty" data-testid="products-empty">
          <h2>No products yet.</h2>
          <p className="secondary">Add what you sell, like pomade or beard oil. Then you can sell it at checkout, and clients see it in the app.</p>
        </div>
      ) : (
        <ul className="biz-products" role="list">
          {products.map((product) => (
            <ProductCard
              key={product.id}
              product={product}
              onEdit={() => {
                setMessage(null);
                setWarning(null);
                setEditing(product);
              }}
              onDelete={() => {
                setDeleteError(null);
                setDeleting(product);
              }}
            />
          ))}
        </ul>
      )}

      <SidePanel
        open={editing !== null}
        title={editing === 'new' ? 'Add a product' : editing ? `Edit ${editing.name}` : ''}
        onClose={() => setEditing(null)}
        testId="product-panel"
      >
        {editing !== null ? (
          <Editor
            key={editing === 'new' ? 'new' : editing.id}
            product={editing === 'new' ? null : editing}
            onCancel={() => setEditing(null)}
            onSaved={(saved, problem) => {
              setEditing(null);
              setMessage(problem ? null : `Saved ${saved.name}.`);
              setWarning(problem ?? null);
              list.reload();
            }}
          />
        ) : null}
      </SidePanel>

      <Dialog
        open={deleting !== null}
        title={deleting ? `Delete ${deleting.name}?` : ''}
        onClose={() => (busy ? undefined : setDeleting(null))}
        testId="confirm-delete-product"
        actions={
          <>
            <button type="button" className="button button--secondary" onClick={() => setDeleting(null)} disabled={busy}>
              Keep it
            </button>
            <button type="button" className="button button--danger" onClick={() => void remove()} disabled={busy}>
              {busy ? 'Deleting…' : 'Delete product'}
            </button>
          </>
        }
      >
        <p>It comes off checkout and the Izzy Clipz app. Past sales keep its name. This can't be undone.</p>
        {deleteError ? (
          <p className="field__error" role="alert">
            <Icon name="error" />
            <span>{deleteError}</span>
          </p>
        ) : null}
      </Dialog>
    </div>
  );
}
