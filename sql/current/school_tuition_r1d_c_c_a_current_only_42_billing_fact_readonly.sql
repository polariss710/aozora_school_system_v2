-- R1D-C-C-A: fixed 42 current-only tuition candidate billing-fact audit.
-- SELECT/readonly DO only. No temporary object, DDL, DML, write RPC, or business write.
\pset pager off
\set ON_ERROR_STOP on

begin isolation level repeatable read read only;

select transaction_timestamp() as r1d_c_c_a_school_audit_transaction_at;

do $audit$
declare
  v record;
  v_group record;
begin
  with manifest(
    planned_lesson_id, expected_old31_hash, expected_student_id, expected_student_name,
    expected_business_entity_id, expected_year_month, expected_actual_lesson_id,
    expected_settlement_id, expected_income_id, expected_account_transaction_id,
    expected_evidence_hash
  ) as (values
    ('495c035a-68f7-42a1-b2a9-28b89ee01d6b'::uuid,'5d3ad276618bc01bae27b6b43a83e978','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','2c2f34a3-f553-4d11-b1e4-d92c553fbb0c'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'ab027f173099b22536eb6c4edb73268a'),
    ('747398ab-db47-493a-8047-4da69174e32b'::uuid,'f9fe1a977a030e519db136cf153bfb9b','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','002875ac-4b12-4f83-b752-d5972d8bb7fa'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'77f932de5a1f4948ece4dee63344b74d'),
    ('8dce41c6-9df0-45e0-bd19-46aeb5fffedc'::uuid,'8645bf1604c52df8438e31a6c1d5fb78','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','511d1cfd-b570-4ee0-a827-9fbec8768743'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'fc69b063c6adcff5daa1241c4fbbbb3a'),
    ('8e778948-194f-40a0-9c6f-cfa3d8637c22'::uuid,'ebddcfc08659025b0011e1a7939bc58b','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','7209bf5d-1916-4f61-bb4c-41dd0b667028'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'d2ec92c9952ad1468ea76a7833892933'),
    ('94e720de-0715-442f-a32a-848a31af3440'::uuid,'ace9d0e97b6dff47bc066f9c8ece3bec','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','daa403bd-4c8b-4752-a1a6-717c9270f661'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'03d32132cd4c5ffeee63c9c18d110d6c'),
    ('a25f02e1-1855-40e6-823d-93789a9ddea7'::uuid,'c26b1fb170e7c027da17368b509e9414','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','4459aef2-735a-42bb-882d-e473571398cf'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'462a681344ec346e3d46dfa6ed71e871'),
    ('dd5a4236-f236-4c41-bbb8-84e1907531db'::uuid,'b9b96d7152e7d5b4a5a8d532f4639001','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','d14ea4da-743a-41f6-8203-cea07f59cfb7'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'ab4973e72027cd86c8e9e04e5fa5e771'),
    ('ed2b7a74-6f6e-4448-8d84-c610754dfb8f'::uuid,'bbda62e926307d064dab6716c37b9c26','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','b2967413-882f-416f-b038-be8520e934a7'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'bfde93b7cbf347135bb05411e2bdd2e4'),
    ('ef7e9696-f655-4b0f-b627-cc51975e6515'::uuid,'dfe00f02fdf6128365ac163438061ba6','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','d53292ea-74c0-43ec-9b94-a4d22a0acaf4'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'a2c6783aae17babbab3a9185a27254fd'),
    ('fddeae0d-47b6-4e4b-9f6b-ade92d3de922'::uuid,'5e2a2aa03a1ea38ea64360865a3f6668','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','2fc6bac6-7324-4bef-ad5d-a25ffcefb168'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'50fe1695e7fee1def843bed90b90a929'),
    ('200cfd39-f61f-4ac4-9f0e-5cc3d885f670'::uuid,'3ac1a3f26dacdcce8cfc764674ddf013','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','62735cb7-bddc-4b96-bd16-ba74842c7c47'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'b057a252bf3ede3077ed3c64bc051428'),
    ('2852a46d-9d9d-4db6-8247-df3cc50725d8'::uuid,'af036483cc8ed66939bf37d2ee3af1ea','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','c60bdbe6-9bcf-4f6a-8bc4-333ac027ede9'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'40c87fe0f28b4f6d4e8904265b53163e'),
    ('4724f45b-c66c-4ae2-b4ab-a1f06e0d545f'::uuid,'1ca747eb81bab16875f524c75798210c','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','a6bc3f1e-717e-4933-89b9-efb8e956726d'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'0e21f1a0796608eed919fe209f0d2a67'),
    ('606d7dfe-3eb6-4884-a0c6-75a1ccc8e335'::uuid,'094ad9e4c6b583beeb36a2bc856296e0','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','8cd37bd7-cfeb-482c-90f9-4a74144d658b'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'865910b9f721492c7fb10f273540b5e1'),
    ('ada45346-50cd-41ce-9568-71d8bb1038a1'::uuid,'1f136ac621568d18a5c5174969f578b1','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','b675f59e-edbd-4cdd-a001-b081375439a3'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'224928ef89ad740376016185db7a8bd8'),
    ('cc24c61f-91d7-49d8-bbfc-73e13e4e7841'::uuid,'4637b1df60bd0b36f9fded098cb20a19','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','e34a3a1f-83b4-4776-81b4-ef8f8165436e'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'28ca3351359d79139838b83b789b352d'),
    ('cdebfb82-e551-4598-bfc5-70e540f438e8'::uuid,'dc459956de00a1d6a40255cd91e581a1','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','c79b2cce-4372-4720-a565-995e18e7c318'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'787dff73f5917bacaa58e3939dfc1eb2'),
    ('e4ac1818-4d2f-4f3f-8979-65ab934f64fc'::uuid,'2932d2a64f095f6c7485f549a51a3541','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','ff6f9dd7-5b6c-4f47-90e9-9531f72e4ca3'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'f32adf79910bbb0503c785994aa94779'),
    ('f99c2359-d9de-4603-a6ed-5b173b94d150'::uuid,'9c6462008676151f4325d3f150527422','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','e0ce2693-0d38-4018-90a2-e8a78de2774f'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'2ca2030d9b531e19bc9c7446f0ba267f'),
    ('ff1f1f7e-671f-48db-885e-14d0a808caed'::uuid,'4a68f6108d276eb01a1e735d6a8e203a','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','4818624b-9302-446d-8982-c5ed09a9f50f'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'21a95d17b396c48ef81137201116e662'),
    ('05246e13-b353-428b-a5cc-2da1cf4e903a'::uuid,'00634dd5baea89050eb7aaf82b7f2dfc','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','bf9d3520-1a31-4605-bb17-e1eda5ef89a3'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'58e7c84bd7d4756e89c9b62c093daae4'),
    ('0aa5af82-783c-4164-b0a1-1ee1289e7d71'::uuid,'9490438221f5184ec7500f53e3d8d12f','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','a2eb187e-d3ec-464b-9710-b0a63db6ab10'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'217d9b2d112de6532d1f59cde0d137f1'),
    ('1309c4cc-8abc-43ae-bde9-c7a9634a5aca'::uuid,'b0a8da4de95646f50771edcb1435a3c4','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','7bb82294-33ba-4f28-b19d-d63623c5e659'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'6ad46d5bead5416e333001007b8e5341'),
    ('2ed4a45c-423f-4eb6-8dcf-ae99a2d78e8a'::uuid,'f640eacc94ff817604d944b3fade8ef2','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','6f0d528b-f414-4632-814e-d965b1f2960e'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'2bc73f067629eda052bec091dd9666e5'),
    ('50d2aeee-538d-4582-8a3c-5fb692cd9f07'::uuid,'f78e435fe7970e3c68468fcbb0d426f1','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','4c974e87-3d7b-44ee-8a73-53149e3d9a8e'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'773dc32b89f50888c4255165b333b221'),
    ('b1d25f4b-d95b-4a39-8e87-2bc9a0382b6b'::uuid,'529eb5bd838376040b4b2d0af1544315','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','f29301e0-4e8a-46c8-8cd6-21edd16409e2'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'f9f9620735a9f7c21a323e49bdc27e16'),
    ('b53d5c38-edcf-4e5c-ac38-286030abef81'::uuid,'ef6e38d4bffacc60af9f484ac4f92528','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','34e930c9-63cd-4b91-a027-0d5a7ea16517'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'fa8a16544c46815aa0399a9febd950b8'),
    ('cf3236a0-21f5-4fd3-8622-42a20aa19ebd'::uuid,'b6f95f21e49bb3baa3665902a1484b26','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','1c93d2be-c0c6-4e0b-a220-b7df04ab18ed'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'555c02f1552a7684df9fe7eb739d6ae7'),
    ('e131726d-b55d-4795-aeff-6fdf966b5017'::uuid,'b19ac2cafe2121c7342917190cf724d4','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','ccac353f-d4b6-4698-ad4f-288e6cf7c613'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'3fada3574592978db2f6368a729fc5d7'),
    ('e3d729b4-4aab-480a-b574-cb02dae0ec71'::uuid,'f055310406a7b05f983598e0f2d3a97f','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','8112c37e-fc63-4b2b-b4a2-25ee241a143c'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'4a4e9b5dcb916830697eab83f99282ae'),
    ('e85b6f77-87ae-42bd-bef4-60ebf4d307d0'::uuid,'412b0d286b8fd53ed0902a9ec73d748a','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','1a951d5f-030b-4656-929e-36426646b1d5'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'90f6344d0145dd8cb9709bc022d918d7'),
    ('faed40b8-a819-4224-8da1-6e463dde4de7'::uuid,'947e35d6efb510baf06c184e081f3e05','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','c6533183-1553-46f1-bbf6-7e2508383d81'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'e6f91fe9a90a631e0adab74f3aeb07a0'),
    ('1f767cd5-a265-4c4a-8b99-58f0e0ad4c09'::uuid,'218ee1cca4735749e499f5a1207798a9','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','bc924326-5913-4902-9169-690f34b11df8'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'64f5099af2f7439c648d0e871d69fe98'),
    ('2def09c2-b6ac-4b5d-bbd1-5b1b7fee6037'::uuid,'fee3f05ad997a6cd944be6683207c319','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','e7b2eb2c-a974-425b-8e0e-175e797e8601'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'a893d73c57144e7c0e2f5f6f6cd989d7'),
    ('458017c5-ab50-44c8-a304-8851a73b3ce3'::uuid,'16f6fad84f976476e8ed75a7d730431e','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','aefaa674-9fe4-4874-bf35-e97c8e2c89dc'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'012474619190fc41b663012abdc6f09f'),
    ('632a3bb3-1ebb-4941-9e22-98c07d829695'::uuid,'a95c00ea2914f1180bdcdd6a298e491e','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','c5298639-038d-4b89-9df4-974367ab7c0c'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'0ec1875296531416c0d32b9cceac4fae'),
    ('79356de1-f6cb-4d80-811c-9e78c5b3672d'::uuid,'0cfe12d96227e538431d2ea07b6757e7','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','fbbd5dc8-294a-4cfb-967a-6f27ad97391f'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'520926b164318cb92cf064c3c2e57946'),
    ('7e5730ec-ad51-4f8b-87a6-c4cc225b6ede'::uuid,'c581ebfc9cbefd0ec01304ff9ae0532f','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','05451028-ecdb-41d2-8077-baf8e1ad3e97'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'879293d0353a04b43916eb48ac620aa1'),
    ('a4316220-13aa-486d-8262-f20d4de6a436'::uuid,'0c251281cf06743de80f4ada86be1f03','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','90cd07c4-4b18-43ec-a6c2-c7ed46988cd6'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'184da0d3e1382c71b376c5a343fe34e1'),
    ('d722a147-6ada-44e6-8caf-85bf09e8af3c'::uuid,'7e885c1d2cde3a5cb5fb3b60d5e0a2ad','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','f9b85a6f-36ae-4f57-b1a6-8d630bece00b'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'692b50a0042c7702b6aa0a7a8606d870'),
    ('dbadbee8-b460-4671-ac16-44021cbe599b'::uuid,'8864b522f4c3fdc326212f3513506e0e','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','1cbeb207-ca6d-48bf-b6a5-f89b6ecc8687'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'a7fa64a41493445208822092e3cf4bd7'),
    ('ee682a14-dbea-4480-966a-34fafb9b5902'::uuid,'46172777e57e72d4d3b6e5d40447d588','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','840d3f42-dbd2-408c-8ecd-b9a89fa74411'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'0f9d4cb4541b850d8784be2c2d09fb5c')
  ),
  current_candidates as (
    select distinct candidate.planned_lesson_id
    from public.school_students student
    join (
      select distinct student_id, year_month
      from public.school_lesson_records
      where app_type='school' and lesson_type='planned'
    ) scope on scope.student_id=student.id
    cross join lateral public.school_list_student_tuition_candidates(
      student.id,student.business_entity_id,scope.year_month,false
    ) candidate
    where candidate.candidate_status='candidate'
  ),
  new_field_candidates as (
    select distinct candidate.planned_lesson_id
    from public.school_lesson_records lesson
    cross join lateral public.school_list_student_tuition_candidates(
      lesson.student_id,lesson.business_entity_id,lesson.billing_month,false
    ) candidate
    where lesson.app_type='school'
      and lesson.lesson_type='planned'
      and lesson.billing_month is not null
      and lesson.billing_week_start_date is not null
      and lesson.student_settlement_month=lesson.billing_month
      and lesson.billing_month_source is not null
      and lesson.billing_month_decided_at is not null
      and public.school_is_valid_tuition_billing_period(
        lesson.billing_month,lesson.billing_week_start_date
      )
      and candidate.planned_lesson_id=lesson.id
      and candidate.candidate_status='candidate'
  ),
  current_only as (
    select * from current_candidates except select * from new_field_candidates
  ),
  new_only as (
    select * from new_field_candidates except select * from current_candidates
  ),
  checked as (
    select manifest.*,
           lesson.id matched_lesson_id,
           md5((to_jsonb(lesson)-'billing_month'-'billing_week_start_date'
             -'scheduled_lesson_date'-'student_settlement_month'
             -'billing_month_source'-'billing_month_decided_at')::text) current_old31_hash,
           student.display_name current_student_name,
           actual.id actual_lesson_id,actual.status actual_status,
           actual.created_at actual_created_at,
           settlement.id settlement_id,settlement.locked_at,
           income.id income_id,transaction_row.id account_transaction_id,
           md5(jsonb_build_object(
             'planned_lesson_id',lesson.id,
             'old31_hash',md5((to_jsonb(lesson)-'billing_month'-'billing_week_start_date'
               -'scheduled_lesson_date'-'student_settlement_month'
               -'billing_month_source'-'billing_month_decided_at')::text),
             'actual_lesson_id',actual.id,'settlement_id',settlement.id,
             'income_id',income.id,'account_transaction_id',transaction_row.id,
             'classification','exclude_reviewable_medium'
           )::text) current_evidence_hash,
           (select count(*) from public.school_lesson_records sibling
            where sibling.lesson_type='actual'
              and sibling.planned_lesson_id=lesson.id) actual_siblings,
           lesson.student_id=actual.student_id same_student,
           lesson.business_entity_id is not distinct from actual.business_entity_id same_entity,
           lesson.subject_id=actual.subject_id same_subject,
           lesson.teacher_id=actual.teacher_id same_teacher,
           lesson.duration_hours=actual.duration_hours same_duration,
           lesson.lesson_fee=actual.lesson_fee same_fee,
           lesson.year_month=actual.year_month same_month
    from manifest
    left join public.school_lesson_records lesson
      on lesson.id=manifest.planned_lesson_id
    left join public.school_students student on student.id=lesson.student_id
    left join public.school_lesson_records actual
      on actual.lesson_type='actual'
     and actual.id=manifest.expected_actual_lesson_id
     and actual.planned_lesson_id=lesson.id
    left join public.school_student_monthly_settlements settlement
      on settlement.id=manifest.expected_settlement_id
     and settlement.student_id=lesson.student_id
     and settlement.business_entity_id is not distinct from lesson.business_entity_id
     and settlement.year_month=lesson.year_month
     and settlement.settlement_status='locked'
    left join public.school_income_records income
      on income.id=manifest.expected_income_id
     and income.student_id=lesson.student_id
     and income.business_entity_id is not distinct from lesson.business_entity_id
     and coalesce(income.settlement_month,income.year_month)=lesson.year_month
     and income.income_category='tuition'
     and income.status='received'
     and coalesce(income.include_in_student_settlement,true)
    left join public.school_account_transactions transaction_row
      on transaction_row.id=manifest.expected_account_transaction_id
     and transaction_row.related_table='school_income_records'
     and transaction_row.related_id=income.id
  )
  select
    (select count(*) from manifest) manifest_rows,
    (select count(distinct planned_lesson_id) from manifest) manifest_distinct_rows,
    (select count(*) from current_candidates) current_rows,
    (select count(*) from new_field_candidates) new_rows,
    (select count(*) from current_only) current_only_rows,
    (select count(*) from new_only) new_only_rows,
    (select count(*) from current_candidates c join new_field_candidates n using(planned_lesson_id))
      intersection_rows,
    (select count(*) from current_only c left join manifest m using(planned_lesson_id)
      where m.planned_lesson_id is null) current_only_missing_manifest,
    (select count(*) from manifest m left join current_only c using(planned_lesson_id)
      where c.planned_lesson_id is null) manifest_not_current_only,
    (select count(*) from checked where matched_lesson_id is null) missing_lessons,
    (select count(*) from checked
      where current_old31_hash<>expected_old31_hash
         or expected_student_id<>(select student_id from public.school_lesson_records
                                  where id=checked.planned_lesson_id)
         or current_student_name<>expected_student_name
         or expected_business_entity_id is distinct from
            (select business_entity_id from public.school_lesson_records
             where id=checked.planned_lesson_id)
         or expected_year_month<>(select year_month from public.school_lesson_records
                                  where id=checked.planned_lesson_id)) lesson_drift,
    (select count(*) from checked
      where actual_lesson_id is null or settlement_id is null or income_id is null
         or account_transaction_id is null) evidence_missing,
    (select count(*) from checked
      where current_evidence_hash<>expected_evidence_hash) evidence_hash_drift,
    (select count(*) from checked where actual_siblings<>1) non_single_actual,
    (select count(*) from checked where not(same_student and same_entity and same_subject
      and same_teacher and same_duration and same_fee and same_month)) actual_business_drift,
    (select count(*) from checked where actual_created_at>locked_at) actual_after_lock,
    (select count(*) from checked where actual_status='completed') completed_actual,
    (select count(*) from checked where actual_status='makeup_completed') makeup_actual,
    (select md5(string_agg(expected_old31_hash,'' order by planned_lesson_id::text))
      from manifest) old31_aggregate_hash,
    (select md5(string_agg(expected_evidence_hash,'' order by planned_lesson_id::text))
      from manifest) evidence_aggregate_hash
  into v;

  if v.manifest_rows<>42 or v.manifest_distinct_rows<>42
     or v.current_rows<>160 or v.new_rows<>118 or v.current_only_rows<>42
     or v.new_only_rows<>0 or v.intersection_rows<>118
     or v.current_only_missing_manifest<>0 or v.manifest_not_current_only<>0
     or v.missing_lessons<>0 or v.lesson_drift<>0 or v.evidence_missing<>0
     or v.evidence_hash_drift<>0 or v.non_single_actual<>0
     or v.actual_business_drift<>0 or v.actual_after_lock<>0
     or v.completed_actual<>41 or v.makeup_actual<>1
     or v.old31_aggregate_hash<>'dc6cd4ad206cc09ed5c02dfe6da5462b'
     or v.evidence_aggregate_hash<>'dc2546bff536942650db58e437d37f0e' then
    raise exception 'R1D-C-C-A fixed-42 baseline or evidence drift: %',to_jsonb(v);
  end if;

  for v_group in
    with manifest(planned_lesson_id) as (values
      ('495c035a-68f7-42a1-b2a9-28b89ee01d6b'::uuid),
      ('747398ab-db47-493a-8047-4da69174e32b'::uuid),
      ('8dce41c6-9df0-45e0-bd19-46aeb5fffedc'::uuid),
      ('8e778948-194f-40a0-9c6f-cfa3d8637c22'::uuid),
      ('94e720de-0715-442f-a32a-848a31af3440'::uuid),
      ('a25f02e1-1855-40e6-823d-93789a9ddea7'::uuid),
      ('dd5a4236-f236-4c41-bbb8-84e1907531db'::uuid),
      ('ed2b7a74-6f6e-4448-8d84-c610754dfb8f'::uuid),
      ('ef7e9696-f655-4b0f-b627-cc51975e6515'::uuid),
      ('fddeae0d-47b6-4e4b-9f6b-ade92d3de922'::uuid),
      ('200cfd39-f61f-4ac4-9f0e-5cc3d885f670'::uuid),
      ('2852a46d-9d9d-4db6-8247-df3cc50725d8'::uuid),
      ('4724f45b-c66c-4ae2-b4ab-a1f06e0d545f'::uuid),
      ('606d7dfe-3eb6-4884-a0c6-75a1ccc8e335'::uuid),
      ('ada45346-50cd-41ce-9568-71d8bb1038a1'::uuid),
      ('cc24c61f-91d7-49d8-bbfc-73e13e4e7841'::uuid),
      ('cdebfb82-e551-4598-bfc5-70e540f438e8'::uuid),
      ('e4ac1818-4d2f-4f3f-8979-65ab934f64fc'::uuid),
      ('f99c2359-d9de-4603-a6ed-5b173b94d150'::uuid),
      ('ff1f1f7e-671f-48db-885e-14d0a808caed'::uuid),
      ('05246e13-b353-428b-a5cc-2da1cf4e903a'::uuid),
      ('0aa5af82-783c-4164-b0a1-1ee1289e7d71'::uuid),
      ('1309c4cc-8abc-43ae-bde9-c7a9634a5aca'::uuid),
      ('2ed4a45c-423f-4eb6-8dcf-ae99a2d78e8a'::uuid),
      ('50d2aeee-538d-4582-8a3c-5fb692cd9f07'::uuid),
      ('b1d25f4b-d95b-4a39-8e87-2bc9a0382b6b'::uuid),
      ('b53d5c38-edcf-4e5c-ac38-286030abef81'::uuid),
      ('cf3236a0-21f5-4fd3-8622-42a20aa19ebd'::uuid),
      ('e131726d-b55d-4795-aeff-6fdf966b5017'::uuid),
      ('e3d729b4-4aab-480a-b574-cb02dae0ec71'::uuid),
      ('e85b6f77-87ae-42bd-bef4-60ebf4d307d0'::uuid),
      ('faed40b8-a819-4224-8da1-6e463dde4de7'::uuid),
      ('1f767cd5-a265-4c4a-8b99-58f0e0ad4c09'::uuid),
      ('2def09c2-b6ac-4b5d-bbd1-5b1b7fee6037'::uuid),
      ('458017c5-ab50-44c8-a304-8851a73b3ce3'::uuid),
      ('632a3bb3-1ebb-4941-9e22-98c07d829695'::uuid),
      ('79356de1-f6cb-4d80-811c-9e78c5b3672d'::uuid),
      ('7e5730ec-ad51-4f8b-87a6-c4cc225b6ede'::uuid),
      ('a4316220-13aa-486d-8262-f20d4de6a436'::uuid),
      ('d722a147-6ada-44e6-8caf-85bf09e8af3c'::uuid),
      ('dbadbee8-b460-4671-ac16-44021cbe599b'::uuid),
      ('ee682a14-dbea-4480-966a-34fafb9b5902'::uuid)
    ),
    expected(student_name,year_month,target_rows,target_hours,target_jpy,
                  planned_month_jpy,actual_month_jpy,received_jpy) as (values
      ('陈加恩','2026-05',10,20::numeric,170000::numeric,204000::numeric,170000::numeric,204000::numeric),
      ('陈红卓','2026-05',10,20::numeric,170000::numeric,204000::numeric,187000::numeric,204000::numeric),
      ('陈加恩','2026-06',12,24::numeric,204000::numeric,204000::numeric,204000::numeric,204000::numeric),
      ('陈红卓','2026-06',10,20::numeric,170000::numeric,204000::numeric,187000::numeric,204000::numeric)
    ),
    actual as (
      select student.display_name student_name,lesson.year_month,
             count(*) target_rows,sum(lesson.duration_hours) target_hours,
             sum(lesson.lesson_fee) target_jpy,
             settlement.planned_lesson_fee_jpy planned_month_jpy,
             settlement.actual_lesson_fee_jpy actual_month_jpy,
             settlement.received_jpy,
             settlement.received_cny,settlement.received_equivalent_cny,
             settlement.adjustment_amount_cny,settlement.carryover_amount_cny,
             count(distinct settlement.id) settlement_rows,
             count(distinct income.id) income_rows,
             count(distinct transaction_row.id) transaction_rows,
             count(distinct bill.id) bill_rows,
             count(distinct relation.id) relation_rows,
             count(distinct payment.id) payment_rows,
             count(distinct linkage.id) cash_linkage_rows
      from public.school_lesson_records lesson
      join public.school_students student on student.id=lesson.student_id
      join public.school_student_monthly_settlements settlement
        on settlement.student_id=lesson.student_id
       and settlement.business_entity_id is not distinct from lesson.business_entity_id
       and settlement.year_month=lesson.year_month and settlement.settlement_status='locked'
      join public.school_income_records income
        on income.student_id=lesson.student_id
       and income.business_entity_id is not distinct from lesson.business_entity_id
       and coalesce(income.settlement_month,income.year_month)=lesson.year_month
       and income.income_category='tuition' and income.status='received'
       and coalesce(income.include_in_student_settlement,true)
      join public.school_account_transactions transaction_row
        on transaction_row.related_table='school_income_records'
       and transaction_row.related_id=income.id
      left join public.school_student_tuition_bills bill
        on bill.student_id=lesson.student_id
       and bill.business_entity_id is not distinct from lesson.business_entity_id
       and bill.billing_month=lesson.year_month
      left join public.school_student_tuition_bill_lessons relation
        on relation.planned_lesson_id=lesson.id
      left join public.school_student_payments payment
        on payment.student_id=lesson.student_id
       and payment.business_entity_id is not distinct from lesson.business_entity_id
       and payment.year_month=lesson.year_month
      left join public.school_personal_cash_income_linkage_events linkage
        on linkage.income_record_id=income.id
      where lesson.id in (select planned_lesson_id from manifest)
      group by student.display_name,lesson.year_month,
               settlement.planned_lesson_fee_jpy,settlement.actual_lesson_fee_jpy,
               settlement.received_jpy,settlement.received_cny,
               settlement.received_equivalent_cny,settlement.adjustment_amount_cny,
               settlement.carryover_amount_cny
    )
    select expected.*,actual.target_rows actual_target_rows,
           actual.target_hours actual_target_hours,actual.target_jpy actual_target_jpy,
           actual.planned_month_jpy actual_planned_month_jpy,
           actual.actual_month_jpy actual_actual_month_jpy,
           actual.received_jpy actual_received_jpy,
           actual.received_cny,actual.received_equivalent_cny,
           actual.settlement_rows,actual.income_rows,actual.transaction_rows,
           actual.bill_rows,actual.relation_rows,actual.payment_rows,actual.cash_linkage_rows
    from expected join actual using(student_name,year_month)
  loop
    if v_group.actual_target_rows<>v_group.target_rows
       or v_group.actual_target_hours<>v_group.target_hours
       or v_group.actual_target_jpy<>v_group.target_jpy
       or v_group.actual_planned_month_jpy<>v_group.planned_month_jpy
       or v_group.actual_actual_month_jpy<>v_group.actual_month_jpy
       or v_group.actual_received_jpy<>v_group.received_jpy
       or v_group.received_cny<>0
       or v_group.settlement_rows<>1 or v_group.income_rows<>1
       or v_group.transaction_rows<>1 or v_group.bill_rows<>0
       or v_group.relation_rows<>0 or v_group.payment_rows<>0
       or v_group.cash_linkage_rows<>0 then
      raise exception 'R1D-C-C-A monthly evidence drift: %',to_jsonb(v_group);
    end if;
  end loop;

  if (select count(*) from public.school_lesson_records)<>626
     or (select count(*) from public.school_lesson_records where lesson_type='planned')<>397
     or (select count(*) from public.school_lesson_records where lesson_type='actual')<>229
     or (select count(*) from public.school_lesson_records
         where billing_month is not null)<>118
     or (select count(*) from public.school_lesson_records
         where scheduled_lesson_date is not null)<>0
     or (select count(*) from public.school_tuition_billing_attribution_override_audit)<>0
     or not exists (select 1 from public.school_feature_gates
                    where feature_key='student_tuition_preview'
                      and state='validation_preview_only')
     or not exists (select 1 from public.school_feature_gates
                    where feature_key='student_tuition_generate' and state='blocked')
     or not exists (select 1 from public.school_feature_gates
                    where feature_key='student_tuition_cash_submit' and state='blocked') then
    raise exception 'R1D-C-C-A global lesson baseline drift';
  end if;
end
$audit$;

-- Fixed Manifest B: all 42 are reviewable monthly evidence, not lesson-level proof.
with manifest(
  planned_lesson_id, expected_old31_hash, expected_student_id, expected_student_name,
  expected_business_entity_id, expected_year_month, expected_actual_lesson_id,
  expected_settlement_id, expected_income_id, expected_account_transaction_id,
  expected_evidence_hash
) as (values
    ('495c035a-68f7-42a1-b2a9-28b89ee01d6b'::uuid,'5d3ad276618bc01bae27b6b43a83e978','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','2c2f34a3-f553-4d11-b1e4-d92c553fbb0c'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'ab027f173099b22536eb6c4edb73268a'),
    ('747398ab-db47-493a-8047-4da69174e32b'::uuid,'f9fe1a977a030e519db136cf153bfb9b','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','002875ac-4b12-4f83-b752-d5972d8bb7fa'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'77f932de5a1f4948ece4dee63344b74d'),
    ('8dce41c6-9df0-45e0-bd19-46aeb5fffedc'::uuid,'8645bf1604c52df8438e31a6c1d5fb78','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','511d1cfd-b570-4ee0-a827-9fbec8768743'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'fc69b063c6adcff5daa1241c4fbbbb3a'),
    ('8e778948-194f-40a0-9c6f-cfa3d8637c22'::uuid,'ebddcfc08659025b0011e1a7939bc58b','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','7209bf5d-1916-4f61-bb4c-41dd0b667028'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'d2ec92c9952ad1468ea76a7833892933'),
    ('94e720de-0715-442f-a32a-848a31af3440'::uuid,'ace9d0e97b6dff47bc066f9c8ece3bec','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','daa403bd-4c8b-4752-a1a6-717c9270f661'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'03d32132cd4c5ffeee63c9c18d110d6c'),
    ('a25f02e1-1855-40e6-823d-93789a9ddea7'::uuid,'c26b1fb170e7c027da17368b509e9414','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','4459aef2-735a-42bb-882d-e473571398cf'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'462a681344ec346e3d46dfa6ed71e871'),
    ('dd5a4236-f236-4c41-bbb8-84e1907531db'::uuid,'b9b96d7152e7d5b4a5a8d532f4639001','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','d14ea4da-743a-41f6-8203-cea07f59cfb7'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'ab4973e72027cd86c8e9e04e5fa5e771'),
    ('ed2b7a74-6f6e-4448-8d84-c610754dfb8f'::uuid,'bbda62e926307d064dab6716c37b9c26','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','b2967413-882f-416f-b038-be8520e934a7'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'bfde93b7cbf347135bb05411e2bdd2e4'),
    ('ef7e9696-f655-4b0f-b627-cc51975e6515'::uuid,'dfe00f02fdf6128365ac163438061ba6','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','d53292ea-74c0-43ec-9b94-a4d22a0acaf4'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'a2c6783aae17babbab3a9185a27254fd'),
    ('fddeae0d-47b6-4e4b-9f6b-ade92d3de922'::uuid,'5e2a2aa03a1ea38ea64360865a3f6668','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','2fc6bac6-7324-4bef-ad5d-a25ffcefb168'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'50fe1695e7fee1def843bed90b90a929'),
    ('200cfd39-f61f-4ac4-9f0e-5cc3d885f670'::uuid,'3ac1a3f26dacdcce8cfc764674ddf013','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','62735cb7-bddc-4b96-bd16-ba74842c7c47'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'b057a252bf3ede3077ed3c64bc051428'),
    ('2852a46d-9d9d-4db6-8247-df3cc50725d8'::uuid,'af036483cc8ed66939bf37d2ee3af1ea','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','c60bdbe6-9bcf-4f6a-8bc4-333ac027ede9'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'40c87fe0f28b4f6d4e8904265b53163e'),
    ('4724f45b-c66c-4ae2-b4ab-a1f06e0d545f'::uuid,'1ca747eb81bab16875f524c75798210c','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','a6bc3f1e-717e-4933-89b9-efb8e956726d'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'0e21f1a0796608eed919fe209f0d2a67'),
    ('606d7dfe-3eb6-4884-a0c6-75a1ccc8e335'::uuid,'094ad9e4c6b583beeb36a2bc856296e0','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','8cd37bd7-cfeb-482c-90f9-4a74144d658b'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'865910b9f721492c7fb10f273540b5e1'),
    ('ada45346-50cd-41ce-9568-71d8bb1038a1'::uuid,'1f136ac621568d18a5c5174969f578b1','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','b675f59e-edbd-4cdd-a001-b081375439a3'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'224928ef89ad740376016185db7a8bd8'),
    ('cc24c61f-91d7-49d8-bbfc-73e13e4e7841'::uuid,'4637b1df60bd0b36f9fded098cb20a19','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','e34a3a1f-83b4-4776-81b4-ef8f8165436e'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'28ca3351359d79139838b83b789b352d'),
    ('cdebfb82-e551-4598-bfc5-70e540f438e8'::uuid,'dc459956de00a1d6a40255cd91e581a1','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','c79b2cce-4372-4720-a565-995e18e7c318'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'787dff73f5917bacaa58e3939dfc1eb2'),
    ('e4ac1818-4d2f-4f3f-8979-65ab934f64fc'::uuid,'2932d2a64f095f6c7485f549a51a3541','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','ff6f9dd7-5b6c-4f47-90e9-9531f72e4ca3'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'f32adf79910bbb0503c785994aa94779'),
    ('f99c2359-d9de-4603-a6ed-5b173b94d150'::uuid,'9c6462008676151f4325d3f150527422','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','e0ce2693-0d38-4018-90a2-e8a78de2774f'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'2ca2030d9b531e19bc9c7446f0ba267f'),
    ('ff1f1f7e-671f-48db-885e-14d0a808caed'::uuid,'4a68f6108d276eb01a1e735d6a8e203a','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','4818624b-9302-446d-8982-c5ed09a9f50f'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'21a95d17b396c48ef81137201116e662'),
    ('05246e13-b353-428b-a5cc-2da1cf4e903a'::uuid,'00634dd5baea89050eb7aaf82b7f2dfc','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','bf9d3520-1a31-4605-bb17-e1eda5ef89a3'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'58e7c84bd7d4756e89c9b62c093daae4'),
    ('0aa5af82-783c-4164-b0a1-1ee1289e7d71'::uuid,'9490438221f5184ec7500f53e3d8d12f','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','a2eb187e-d3ec-464b-9710-b0a63db6ab10'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'217d9b2d112de6532d1f59cde0d137f1'),
    ('1309c4cc-8abc-43ae-bde9-c7a9634a5aca'::uuid,'b0a8da4de95646f50771edcb1435a3c4','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','7bb82294-33ba-4f28-b19d-d63623c5e659'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'6ad46d5bead5416e333001007b8e5341'),
    ('2ed4a45c-423f-4eb6-8dcf-ae99a2d78e8a'::uuid,'f640eacc94ff817604d944b3fade8ef2','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','6f0d528b-f414-4632-814e-d965b1f2960e'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'2bc73f067629eda052bec091dd9666e5'),
    ('50d2aeee-538d-4582-8a3c-5fb692cd9f07'::uuid,'f78e435fe7970e3c68468fcbb0d426f1','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','4c974e87-3d7b-44ee-8a73-53149e3d9a8e'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'773dc32b89f50888c4255165b333b221'),
    ('b1d25f4b-d95b-4a39-8e87-2bc9a0382b6b'::uuid,'529eb5bd838376040b4b2d0af1544315','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','f29301e0-4e8a-46c8-8cd6-21edd16409e2'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'f9f9620735a9f7c21a323e49bdc27e16'),
    ('b53d5c38-edcf-4e5c-ac38-286030abef81'::uuid,'ef6e38d4bffacc60af9f484ac4f92528','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','34e930c9-63cd-4b91-a027-0d5a7ea16517'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'fa8a16544c46815aa0399a9febd950b8'),
    ('cf3236a0-21f5-4fd3-8622-42a20aa19ebd'::uuid,'b6f95f21e49bb3baa3665902a1484b26','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','1c93d2be-c0c6-4e0b-a220-b7df04ab18ed'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'555c02f1552a7684df9fe7eb739d6ae7'),
    ('e131726d-b55d-4795-aeff-6fdf966b5017'::uuid,'b19ac2cafe2121c7342917190cf724d4','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','ccac353f-d4b6-4698-ad4f-288e6cf7c613'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'3fada3574592978db2f6368a729fc5d7'),
    ('e3d729b4-4aab-480a-b574-cb02dae0ec71'::uuid,'f055310406a7b05f983598e0f2d3a97f','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','8112c37e-fc63-4b2b-b4a2-25ee241a143c'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'4a4e9b5dcb916830697eab83f99282ae'),
    ('e85b6f77-87ae-42bd-bef4-60ebf4d307d0'::uuid,'412b0d286b8fd53ed0902a9ec73d748a','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','1a951d5f-030b-4656-929e-36426646b1d5'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'90f6344d0145dd8cb9709bc022d918d7'),
    ('faed40b8-a819-4224-8da1-6e463dde4de7'::uuid,'947e35d6efb510baf06c184e081f3e05','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','c6533183-1553-46f1-bbf6-7e2508383d81'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'e6f91fe9a90a631e0adab74f3aeb07a0'),
    ('1f767cd5-a265-4c4a-8b99-58f0e0ad4c09'::uuid,'218ee1cca4735749e499f5a1207798a9','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','bc924326-5913-4902-9169-690f34b11df8'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'64f5099af2f7439c648d0e871d69fe98'),
    ('2def09c2-b6ac-4b5d-bbd1-5b1b7fee6037'::uuid,'fee3f05ad997a6cd944be6683207c319','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','e7b2eb2c-a974-425b-8e0e-175e797e8601'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'a893d73c57144e7c0e2f5f6f6cd989d7'),
    ('458017c5-ab50-44c8-a304-8851a73b3ce3'::uuid,'16f6fad84f976476e8ed75a7d730431e','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','aefaa674-9fe4-4874-bf35-e97c8e2c89dc'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'012474619190fc41b663012abdc6f09f'),
    ('632a3bb3-1ebb-4941-9e22-98c07d829695'::uuid,'a95c00ea2914f1180bdcdd6a298e491e','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','c5298639-038d-4b89-9df4-974367ab7c0c'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'0ec1875296531416c0d32b9cceac4fae'),
    ('79356de1-f6cb-4d80-811c-9e78c5b3672d'::uuid,'0cfe12d96227e538431d2ea07b6757e7','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','fbbd5dc8-294a-4cfb-967a-6f27ad97391f'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'520926b164318cb92cf064c3c2e57946'),
    ('7e5730ec-ad51-4f8b-87a6-c4cc225b6ede'::uuid,'c581ebfc9cbefd0ec01304ff9ae0532f','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','05451028-ecdb-41d2-8077-baf8e1ad3e97'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'879293d0353a04b43916eb48ac620aa1'),
    ('a4316220-13aa-486d-8262-f20d4de6a436'::uuid,'0c251281cf06743de80f4ada86be1f03','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','90cd07c4-4b18-43ec-a6c2-c7ed46988cd6'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'184da0d3e1382c71b376c5a343fe34e1'),
    ('d722a147-6ada-44e6-8caf-85bf09e8af3c'::uuid,'7e885c1d2cde3a5cb5fb3b60d5e0a2ad','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','f9b85a6f-36ae-4f57-b1a6-8d630bece00b'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'692b50a0042c7702b6aa0a7a8606d870'),
    ('dbadbee8-b460-4671-ac16-44021cbe599b'::uuid,'8864b522f4c3fdc326212f3513506e0e','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','1cbeb207-ca6d-48bf-b6a5-f89b6ecc8687'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'a7fa64a41493445208822092e3cf4bd7'),
    ('ee682a14-dbea-4480-966a-34fafb9b5902'::uuid,'46172777e57e72d4d3b6e5d40447d588','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','840d3f42-dbd2-408c-8ecd-b9a89fa74411'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'0f9d4cb4541b850d8784be2c2d09fb5c')
)
select manifest.*,lesson.lesson_date,lesson.status,lesson.is_billable,
       lesson.subject_id,lesson.teacher_id,lesson.lesson_count,lesson.duration_hours,
       lesson.unit_price,lesson.lesson_fee,lesson.import_batch_id,lesson.import_source,
       lesson.created_at,lesson.updated_at,
       actual.status actual_status,actual.lesson_date actual_date,
       actual.year_month actual_year_month,actual.teacher_settlement_month,
       actual.duration_hours actual_duration,actual.lesson_fee actual_fee,
       actual.is_billable actual_is_billable,actual.created_at actual_created_at,
       settlement.locked_at,
       'exclude_reviewable_medium' evidence_class
from manifest
join public.school_lesson_records lesson on lesson.id=manifest.planned_lesson_id
join public.school_lesson_records actual on actual.id=manifest.expected_actual_lesson_id
join public.school_student_monthly_settlements settlement
  on settlement.id=manifest.expected_settlement_id
order by manifest.expected_year_month,manifest.expected_student_name,
         manifest.planned_lesson_id::text;

-- Manifest and candidate-scenario summaries.
with manifest(
  planned_lesson_id, expected_old31_hash, expected_student_id, expected_student_name,
  expected_business_entity_id, expected_year_month, expected_actual_lesson_id,
  expected_settlement_id, expected_income_id, expected_account_transaction_id,
  expected_evidence_hash
) as (values
    ('495c035a-68f7-42a1-b2a9-28b89ee01d6b'::uuid,'5d3ad276618bc01bae27b6b43a83e978','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','2c2f34a3-f553-4d11-b1e4-d92c553fbb0c'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'ab027f173099b22536eb6c4edb73268a'),
    ('747398ab-db47-493a-8047-4da69174e32b'::uuid,'f9fe1a977a030e519db136cf153bfb9b','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','002875ac-4b12-4f83-b752-d5972d8bb7fa'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'77f932de5a1f4948ece4dee63344b74d'),
    ('8dce41c6-9df0-45e0-bd19-46aeb5fffedc'::uuid,'8645bf1604c52df8438e31a6c1d5fb78','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','511d1cfd-b570-4ee0-a827-9fbec8768743'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'fc69b063c6adcff5daa1241c4fbbbb3a'),
    ('8e778948-194f-40a0-9c6f-cfa3d8637c22'::uuid,'ebddcfc08659025b0011e1a7939bc58b','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','7209bf5d-1916-4f61-bb4c-41dd0b667028'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'d2ec92c9952ad1468ea76a7833892933'),
    ('94e720de-0715-442f-a32a-848a31af3440'::uuid,'ace9d0e97b6dff47bc066f9c8ece3bec','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','daa403bd-4c8b-4752-a1a6-717c9270f661'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'03d32132cd4c5ffeee63c9c18d110d6c'),
    ('a25f02e1-1855-40e6-823d-93789a9ddea7'::uuid,'c26b1fb170e7c027da17368b509e9414','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','4459aef2-735a-42bb-882d-e473571398cf'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'462a681344ec346e3d46dfa6ed71e871'),
    ('dd5a4236-f236-4c41-bbb8-84e1907531db'::uuid,'b9b96d7152e7d5b4a5a8d532f4639001','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','d14ea4da-743a-41f6-8203-cea07f59cfb7'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'ab4973e72027cd86c8e9e04e5fa5e771'),
    ('ed2b7a74-6f6e-4448-8d84-c610754dfb8f'::uuid,'bbda62e926307d064dab6716c37b9c26','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','b2967413-882f-416f-b038-be8520e934a7'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'bfde93b7cbf347135bb05411e2bdd2e4'),
    ('ef7e9696-f655-4b0f-b627-cc51975e6515'::uuid,'dfe00f02fdf6128365ac163438061ba6','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','d53292ea-74c0-43ec-9b94-a4d22a0acaf4'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'a2c6783aae17babbab3a9185a27254fd'),
    ('fddeae0d-47b6-4e4b-9f6b-ade92d3de922'::uuid,'5e2a2aa03a1ea38ea64360865a3f6668','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','2fc6bac6-7324-4bef-ad5d-a25ffcefb168'::uuid,'6db58942-7b98-4cb1-aa3d-c40b199e54c5'::uuid,'121d84e6-fc9f-4d47-bd8f-6a3cee096a16'::uuid,'5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1'::uuid,'50fe1695e7fee1def843bed90b90a929'),
    ('200cfd39-f61f-4ac4-9f0e-5cc3d885f670'::uuid,'3ac1a3f26dacdcce8cfc764674ddf013','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','62735cb7-bddc-4b96-bd16-ba74842c7c47'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'b057a252bf3ede3077ed3c64bc051428'),
    ('2852a46d-9d9d-4db6-8247-df3cc50725d8'::uuid,'af036483cc8ed66939bf37d2ee3af1ea','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','c60bdbe6-9bcf-4f6a-8bc4-333ac027ede9'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'40c87fe0f28b4f6d4e8904265b53163e'),
    ('4724f45b-c66c-4ae2-b4ab-a1f06e0d545f'::uuid,'1ca747eb81bab16875f524c75798210c','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','a6bc3f1e-717e-4933-89b9-efb8e956726d'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'0e21f1a0796608eed919fe209f0d2a67'),
    ('606d7dfe-3eb6-4884-a0c6-75a1ccc8e335'::uuid,'094ad9e4c6b583beeb36a2bc856296e0','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','8cd37bd7-cfeb-482c-90f9-4a74144d658b'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'865910b9f721492c7fb10f273540b5e1'),
    ('ada45346-50cd-41ce-9568-71d8bb1038a1'::uuid,'1f136ac621568d18a5c5174969f578b1','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','b675f59e-edbd-4cdd-a001-b081375439a3'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'224928ef89ad740376016185db7a8bd8'),
    ('cc24c61f-91d7-49d8-bbfc-73e13e4e7841'::uuid,'4637b1df60bd0b36f9fded098cb20a19','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','e34a3a1f-83b4-4776-81b4-ef8f8165436e'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'28ca3351359d79139838b83b789b352d'),
    ('cdebfb82-e551-4598-bfc5-70e540f438e8'::uuid,'dc459956de00a1d6a40255cd91e581a1','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','c79b2cce-4372-4720-a565-995e18e7c318'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'787dff73f5917bacaa58e3939dfc1eb2'),
    ('e4ac1818-4d2f-4f3f-8979-65ab934f64fc'::uuid,'2932d2a64f095f6c7485f549a51a3541','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','ff6f9dd7-5b6c-4f47-90e9-9531f72e4ca3'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'f32adf79910bbb0503c785994aa94779'),
    ('f99c2359-d9de-4603-a6ed-5b173b94d150'::uuid,'9c6462008676151f4325d3f150527422','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','e0ce2693-0d38-4018-90a2-e8a78de2774f'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'2ca2030d9b531e19bc9c7446f0ba267f'),
    ('ff1f1f7e-671f-48db-885e-14d0a808caed'::uuid,'4a68f6108d276eb01a1e735d6a8e203a','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-05','4818624b-9302-446d-8982-c5ed09a9f50f'::uuid,'64ae8e85-0edb-468b-8310-1e1d396104e9'::uuid,'18a80ecd-4486-44d6-95ca-324d2030404f'::uuid,'dba70bdc-f6a0-4bbc-ae63-bd1f69837457'::uuid,'21a95d17b396c48ef81137201116e662'),
    ('05246e13-b353-428b-a5cc-2da1cf4e903a'::uuid,'00634dd5baea89050eb7aaf82b7f2dfc','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','bf9d3520-1a31-4605-bb17-e1eda5ef89a3'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'58e7c84bd7d4756e89c9b62c093daae4'),
    ('0aa5af82-783c-4164-b0a1-1ee1289e7d71'::uuid,'9490438221f5184ec7500f53e3d8d12f','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','a2eb187e-d3ec-464b-9710-b0a63db6ab10'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'217d9b2d112de6532d1f59cde0d137f1'),
    ('1309c4cc-8abc-43ae-bde9-c7a9634a5aca'::uuid,'b0a8da4de95646f50771edcb1435a3c4','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','7bb82294-33ba-4f28-b19d-d63623c5e659'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'6ad46d5bead5416e333001007b8e5341'),
    ('2ed4a45c-423f-4eb6-8dcf-ae99a2d78e8a'::uuid,'f640eacc94ff817604d944b3fade8ef2','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','6f0d528b-f414-4632-814e-d965b1f2960e'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'2bc73f067629eda052bec091dd9666e5'),
    ('50d2aeee-538d-4582-8a3c-5fb692cd9f07'::uuid,'f78e435fe7970e3c68468fcbb0d426f1','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','4c974e87-3d7b-44ee-8a73-53149e3d9a8e'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'773dc32b89f50888c4255165b333b221'),
    ('b1d25f4b-d95b-4a39-8e87-2bc9a0382b6b'::uuid,'529eb5bd838376040b4b2d0af1544315','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','f29301e0-4e8a-46c8-8cd6-21edd16409e2'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'f9f9620735a9f7c21a323e49bdc27e16'),
    ('b53d5c38-edcf-4e5c-ac38-286030abef81'::uuid,'ef6e38d4bffacc60af9f484ac4f92528','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','34e930c9-63cd-4b91-a027-0d5a7ea16517'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'fa8a16544c46815aa0399a9febd950b8'),
    ('cf3236a0-21f5-4fd3-8622-42a20aa19ebd'::uuid,'b6f95f21e49bb3baa3665902a1484b26','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','1c93d2be-c0c6-4e0b-a220-b7df04ab18ed'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'555c02f1552a7684df9fe7eb739d6ae7'),
    ('e131726d-b55d-4795-aeff-6fdf966b5017'::uuid,'b19ac2cafe2121c7342917190cf724d4','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','ccac353f-d4b6-4698-ad4f-288e6cf7c613'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'3fada3574592978db2f6368a729fc5d7'),
    ('e3d729b4-4aab-480a-b574-cb02dae0ec71'::uuid,'f055310406a7b05f983598e0f2d3a97f','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','8112c37e-fc63-4b2b-b4a2-25ee241a143c'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'4a4e9b5dcb916830697eab83f99282ae'),
    ('e85b6f77-87ae-42bd-bef4-60ebf4d307d0'::uuid,'412b0d286b8fd53ed0902a9ec73d748a','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','1a951d5f-030b-4656-929e-36426646b1d5'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'90f6344d0145dd8cb9709bc022d918d7'),
    ('faed40b8-a819-4224-8da1-6e463dde4de7'::uuid,'947e35d6efb510baf06c184e081f3e05','881dd60c-b92b-44ae-98e1-98448567a8d2'::uuid,'陈加恩','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','c6533183-1553-46f1-bbf6-7e2508383d81'::uuid,'24c9f706-6eb8-4592-80d2-18446ca6ba42'::uuid,'3176d629-f319-497a-95ae-2366a43cdf7a'::uuid,'fd90b997-d31d-4553-bda3-a9cc2096c404'::uuid,'e6f91fe9a90a631e0adab74f3aeb07a0'),
    ('1f767cd5-a265-4c4a-8b99-58f0e0ad4c09'::uuid,'218ee1cca4735749e499f5a1207798a9','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','bc924326-5913-4902-9169-690f34b11df8'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'64f5099af2f7439c648d0e871d69fe98'),
    ('2def09c2-b6ac-4b5d-bbd1-5b1b7fee6037'::uuid,'fee3f05ad997a6cd944be6683207c319','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','e7b2eb2c-a974-425b-8e0e-175e797e8601'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'a893d73c57144e7c0e2f5f6f6cd989d7'),
    ('458017c5-ab50-44c8-a304-8851a73b3ce3'::uuid,'16f6fad84f976476e8ed75a7d730431e','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','aefaa674-9fe4-4874-bf35-e97c8e2c89dc'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'012474619190fc41b663012abdc6f09f'),
    ('632a3bb3-1ebb-4941-9e22-98c07d829695'::uuid,'a95c00ea2914f1180bdcdd6a298e491e','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','c5298639-038d-4b89-9df4-974367ab7c0c'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'0ec1875296531416c0d32b9cceac4fae'),
    ('79356de1-f6cb-4d80-811c-9e78c5b3672d'::uuid,'0cfe12d96227e538431d2ea07b6757e7','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','fbbd5dc8-294a-4cfb-967a-6f27ad97391f'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'520926b164318cb92cf064c3c2e57946'),
    ('7e5730ec-ad51-4f8b-87a6-c4cc225b6ede'::uuid,'c581ebfc9cbefd0ec01304ff9ae0532f','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','05451028-ecdb-41d2-8077-baf8e1ad3e97'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'879293d0353a04b43916eb48ac620aa1'),
    ('a4316220-13aa-486d-8262-f20d4de6a436'::uuid,'0c251281cf06743de80f4ada86be1f03','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','90cd07c4-4b18-43ec-a6c2-c7ed46988cd6'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'184da0d3e1382c71b376c5a343fe34e1'),
    ('d722a147-6ada-44e6-8caf-85bf09e8af3c'::uuid,'7e885c1d2cde3a5cb5fb3b60d5e0a2ad','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','f9b85a6f-36ae-4f57-b1a6-8d630bece00b'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'692b50a0042c7702b6aa0a7a8606d870'),
    ('dbadbee8-b460-4671-ac16-44021cbe599b'::uuid,'8864b522f4c3fdc326212f3513506e0e','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','1cbeb207-ca6d-48bf-b6a5-f89b6ecc8687'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'a7fa64a41493445208822092e3cf4bd7'),
    ('ee682a14-dbea-4480-966a-34fafb9b5902'::uuid,'46172777e57e72d4d3b6e5d40447d588','eceb2c59-9689-4ec8-9d3f-799b90bfdb27'::uuid,'陈红卓','2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid,'2026-06','840d3f42-dbd2-408c-8ecd-b9a89fa74411'::uuid,'bffa9c9f-27d7-4522-93ed-d64ff629513a'::uuid,'365a26cb-2c25-4b0b-b34b-01bba26c766c'::uuid,'bb124b53-ab20-4c85-aad2-a83bc316132d'::uuid,'0f9d4cb4541b850d8784be2c2d09fb5c')
)
select 'A_exclude_high' manifest_name,0 rows,0 students,0::numeric hours,0::numeric jpy,
       md5('') old31_aggregate_hash,md5('') evidence_aggregate_hash,
       'No immutable lesson-level billing relation or settlement detail exists' conclusion
union all
select 'B_exclude_reviewable_medium',count(*),count(distinct expected_student_id),
       sum(lesson.duration_hours),sum(lesson.lesson_fee),
       md5(string_agg(manifest.expected_old31_hash,'' order by manifest.planned_lesson_id::text)),
       md5(string_agg(manifest.expected_evidence_hash,'' order by manifest.planned_lesson_id::text)),
       'Requires business-owner approval of the fixed 42; monthly receipt cannot be auto-allocated per lesson'
from manifest join public.school_lesson_records lesson on lesson.id=manifest.planned_lesson_id
union all
select 'C_needs_billing',0,0,0,0,md5(''),md5(''),
       'No affirmative unpaid evidence found; do not infer paid status without Manifest B approval'
union all
select 'D_conflict_or_unavailable',0,0,0,0,md5(''),md5(''),
       'No internal contradiction found in current School/Cash evidence';

select * from (values
  ('scheme_1_new_fields_118',118,42,'42 disappear from candidate but are not thereby proven charged; unsafe to switch'),
  ('scheme_2_new_118_plus_manifest_a',118,42,'Manifest A is empty; all 42 remain business-review blockers'),
  ('scheme_3_new_118_plus_approved_a_b',118,0,'Only after explicit approval may fixed Manifest B be excluded as settled history'),
  ('scheme_4_keep_switch_blocked',160,42,'Recommended until fixed Manifest B receives business approval')
) scenario(scenario,candidate_rows,unresolved_current_only,interpretation);

-- Settlement semantics: aggregate snapshot only; no lesson UUID/detail snapshot column.
select column_name,data_type
from information_schema.columns
where table_schema='public'
  and table_name='school_student_monthly_settlements'
order by ordinal_position;

select count(*) as settlement_lesson_detail_table_count
from information_schema.tables
where table_schema='public'
  and table_name in (
    'school_student_monthly_settlement_details',
    'school_student_monthly_settlement_lessons',
    'school_student_settlement_lesson_snapshots'
  );

-- Four monthly snapshots and direct School receipt/account evidence.
select student.display_name,settlement.year_month,settlement.id settlement_id,
       settlement.settlement_status,settlement.created_at,settlement.updated_at,
       settlement.locked_at,settlement.preset_exchange_rate,
       settlement.planned_lesson_fee_jpy,settlement.actual_lesson_fee_jpy,
       settlement.previous_balance_cny,settlement.received_jpy,settlement.received_cny,
       settlement.received_equivalent_cny,settlement.system_difference_cny,
       settlement.adjustment_amount_cny,settlement.adjustment_reason,
       settlement.carryover_amount_cny,
       income.id income_id,income.status income_status,income.amount income_amount,
       income.currency income_currency,income.income_date,income.created_at income_created_at,
       transaction_row.id account_transaction_id,
       transaction_row.transaction_date,transaction_row.amount transaction_amount
from public.school_student_monthly_settlements settlement
join public.school_students student on student.id=settlement.student_id
join public.school_income_records income
  on income.student_id=settlement.student_id
 and income.business_entity_id is not distinct from settlement.business_entity_id
 and coalesce(income.settlement_month,income.year_month)=settlement.year_month
 and income.income_category='tuition' and income.status='received'
 and coalesce(income.include_in_student_settlement,true)
join public.school_account_transactions transaction_row
  on transaction_row.related_table='school_income_records'
 and transaction_row.related_id=income.id
where settlement.id in (
  '6db58942-7b98-4cb1-aa3d-c40b199e54c5',
  '64ae8e85-0edb-468b-8310-1e1d396104e9',
  '24c9f706-6eb8-4592-80d2-18446ca6ba42',
  'bffa9c9f-27d7-4522-93ed-d64ff629513a'
)
order by settlement.year_month,student.display_name;

-- School protected business baselines.
select * from (
  select 1 seq,'lesson_raw37' object_name,count(*) row_count,
         md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),'' order by row_value.id::text),''))
           business_hash
  from public.school_lesson_records row_value
  union all select 2,'lesson_old31',count(*),
         md5(coalesce(string_agg(md5((to_jsonb(row_value)-'billing_month'
           -'billing_week_start_date'-'scheduled_lesson_date'-'student_settlement_month'
           -'billing_month_source'-'billing_month_decided_at')::text),''
           order by row_value.id::text),''))
  from public.school_lesson_records row_value
  union all select 3,'tuition_bill',count(*),
         md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),'' order by row_value.id::text),''))
  from public.school_student_tuition_bills row_value
  union all select 4,'income',count(*),
         md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),'' order by row_value.id::text),''))
  from public.school_income_records row_value
  union all select 5,'billing_identity',count(*),
         md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),'' order by row_value.id::text),''))
  from public.school_student_tuition_billing_identities row_value
  union all select 6,'bill_lesson_relation',count(*),
         md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),'' order by row_value.id::text),''))
  from public.school_student_tuition_bill_lessons row_value
  union all select 7,'migration_batch',count(*),
         md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),'' order by row_value.id::text),''))
  from public.school_business_entity_migration_batches row_value
  union all select 8,'migration_item',count(*),
         md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),'' order by row_value.id::text),''))
  from public.school_business_entity_migration_items row_value
  union all select 9,'student_settlement',count(*),
         md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),'' order by row_value.id::text),''))
  from public.school_student_monthly_settlements row_value
  union all select 10,'settlement_adjustment',count(*),
         md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),'' order by row_value.id::text),''))
  from public.school_student_settlement_adjustments row_value
  union all select 11,'student_payment',count(*),
         md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),'' order by row_value.id::text),''))
  from public.school_student_payments row_value
  union all select 12,'school_account_transaction',count(*),
         md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),'' order by row_value.id::text),''))
  from public.school_account_transactions row_value
  union all select 13,'school_cash_linkage',count(*),
         md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),'' order by row_value.id::text),''))
  from public.school_personal_cash_income_linkage_events row_value
  union all select 14,'teacher_wage_lock',count(*),
         md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),'' order by row_value.id::text),''))
  from public.school_teacher_wage_locks row_value
  union all select 15,'teacher_wage_detail',count(*),
         md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),'' order by row_value.id::text),''))
  from public.school_teacher_wage_lock_details row_value
  union all select 16,'feature_gate',count(*),
         md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),'' order by row_value.feature_key),''))
  from public.school_feature_gates row_value
  union all select 17,'override_audit',count(*),
         md5(coalesce(string_agg(md5(to_jsonb(row_value)::text),'' order by row_value.id::text),''))
  from public.school_tuition_billing_attribution_override_audit row_value
) baseline order by seq;

select feature_key,state
from public.school_feature_gates
where feature_key in (
  'student_tuition_preview','student_tuition_generate','student_tuition_cash_submit'
)
order by feature_key;

commit;
