-- Sellora on Supabase — Storage for store branding images.
--
-- Replaces the inline `data:` URIs Customize store used to write into
-- stores.logo_url/banner_url (lib/core/utils/image_data_url.dart). A picked
-- photo is uploaded to `store-media/{store_id}/...` and the store keeps its
-- public URL (StoreRepository.uploadStoreImage).

-- Public: storefronts show these to anyone, so they're served by URL with
-- no read policy needed. The size cap matches maxPickedImageBytes in the app.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('store-media', 'store-media', true, 2097152,
        array['image/jpeg', 'image/png', 'image/webp', 'image/gif'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Writes are the store owner's alone: the first path segment is the store
-- id, checked with the same owns_store() the stores/products policies use.
create policy "store-media: owner reads own folder"
  on storage.objects for select to authenticated
  using (bucket_id = 'store-media' and public.owns_store((storage.foldername(name))[1]));

create policy "store-media: owner uploads"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'store-media' and public.owns_store((storage.foldername(name))[1]));

create policy "store-media: owner replaces"
  on storage.objects for update to authenticated
  using (bucket_id = 'store-media' and public.owns_store((storage.foldername(name))[1]))
  with check (bucket_id = 'store-media' and public.owns_store((storage.foldername(name))[1]));

create policy "store-media: owner deletes"
  on storage.objects for delete to authenticated
  using (bucket_id = 'store-media' and public.owns_store((storage.foldername(name))[1]));
