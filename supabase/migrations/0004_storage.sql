-- =====================================================================
-- Migração 0004: Storage — bucket privado 'documentos'
--
-- Caminho dos objetos: <IMOVEL_ID>/<categoria>/<arquivo>  (ou holding/…).
-- Quem lê é quem está em pessoas; quem sobe é operacional/admin; quem
-- apaga é admin. O arquivo nunca é público: o painel pede URL assinada.
-- =====================================================================

insert into storage.buckets (id, name, public)
values ('documentos', 'documentos', false)
on conflict (id) do update set public = false;

create policy documentos_storage_ler on storage.objects
  for select using (bucket_id = 'documentos' and e_autorizado());

create policy documentos_storage_subir on storage.objects
  for insert with check (bucket_id = 'documentos' and pode_editar());

create policy documentos_storage_editar on storage.objects
  for update using (bucket_id = 'documentos' and pode_editar())
  with check (bucket_id = 'documentos' and pode_editar());

create policy documentos_storage_apagar on storage.objects
  for delete using (bucket_id = 'documentos' and e_admin());
