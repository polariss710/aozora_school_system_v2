# School V2 学费链P0：R1D-C-C-A 42条current-only候选固定Manifest

- 冻结日期：2026-07-28
- School最终只读事务：`2026-07-28 07:45:34.785059+00`
- Git基线：`eba88297a236cc87303839aa36c54a375c85a872`
- 固定对象：当前权威candidate 160与合法新归属candidate 118的差集42
- old31 aggregate hash：`dc6cd4ad206cc09ed5c02dfe6da5462b`
- evidence aggregate hash：`dc2546bff536942650db58e437d37f0e`
- 业务审批状态：固定Manifest B的42 UUID已获批准作为“历史已收费、未来candidate应排除”的固定业务集合。
- 本批准只确认固定业务集合，不授权回填、candidate函数修改、candidate切换或历史收费关系写入。

## 1. 四类Manifest

| Manifest | 分类 | 行 | 学生 | 月份 | 小时 | JPY | old31 hash | evidence hash |
|---|---|---:|---:|---|---:|---:|---|---|
| A | `exclude_high` | 0 | 0 | - | 0 | 0 | `d41d8cd98f00b204e9800998ecf8427e` | `d41d8cd98f00b204e9800998ecf8427e` |
| B | `exclude_reviewable_medium` | 42 | 2 | 2026-05/06 | 84 | 714,000 | `dc6cd4ad206cc09ed5c02dfe6da5462b` | `dc2546bff536942650db58e437d37f0e` |
| C | `needs_billing` | 0 | 0 | - | 0 | 0 | `d41d8cd98f00b204e9800998ecf8427e` | `d41d8cd98f00b204e9800998ecf8427e` |
| D | `conflict/unavailable` | 0 | 0 | - | 0 | 0 | `d41d8cd98f00b204e9800998ecf8427e` | `d41d8cd98f00b204e9800998ecf8427e` |

Manifest A为空，因为没有任何一条具有immutable lesson级bill relation、bill JSON lesson ID或月结lesson明细快照。Manifest B的42条均有精确actual、locked月结、月度received income和School账户流水，且证据内部可对账；只读数据库证据本身不能自动拆分为每条lesson的直接收费事实。业务负责人现已按本文件固定清单批准Manifest B的42 UUID作为历史已收费集合。Manifest C/D当前为空。

## 2. 分组摘要

| 学生/月 | 行 | 小时 | 目标JPY | 月度planned JPY | 月度actual JPY | received JPY | settlement | income | account transaction |
|---|---:|---:|---:|---:|---:|---:|---|---|---|
| 陈加恩 2026-05 | 10 | 20 | 170,000 | 204,000 | 170,000 | 204,000 | `6db58942-7b98-4cb1-aa3d-c40b199e54c5` | `121d84e6-fc9f-4d47-bd8f-6a3cee096a16` | `5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1` |
| 陈红卓 2026-05 | 10 | 20 | 170,000 | 204,000 | 187,000 | 204,000 | `64ae8e85-0edb-468b-8310-1e1d396104e9` | `18a80ecd-4486-44d6-95ca-324d2030404f` | `dba70bdc-f6a0-4bbc-ae63-bd1f69837457` |
| 陈加恩 2026-06 | 12 | 24 | 204,000 | 204,000 | 204,000 | 204,000 | `24c9f706-6eb8-4592-80d2-18446ca6ba42` | `3176d629-f319-497a-95ae-2366a43cdf7a` | `fd90b997-d31d-4553-bda3-a9cc2096c404` |
| 陈红卓 2026-06 | 10 | 20 | 170,000 | 204,000 | 187,000 | 204,000 | `bffa9c9f-27d7-4522-93ed-d64ff629513a` | `365a26cb-2c25-4b0b-b34b-01bba26c766c` | `bb124b53-ab20-4c85-aad2-a83bc316132d` |

四笔income均为received JPY 204,000，并各有一条同额School `income_adjust`账户流水；tuition bill、normalized relation、student payment、School Cash linkage及Cash DB外部引用均为0。May两组和陈红卓June各另有2条JPY34,000的`pending_makeup` planned；月结以月度聚合保存，不含lesson UUID。业务负责人已明确确认四笔收入是对应月份全部planned课程的学费，包含这6条`pending_makeup`；6条不属于本Manifest B，不因该确认被处理或加入固定42集合。

## 3. Manifest B完整逐行冻结

Evidence hash固定以下字段：planned UUID、old31 hash、actual UUID、settlement UUID、income UUID、School account transaction UUID及分类`exclude_reviewable_medium`。

| # | planned UUID | old31 hash | 学生 | 月份 | actual UUID | settlement UUID | income UUID | account transaction UUID | evidence hash |
|---:|---|---|---|---|---|---|---|---|---|
| 1 | `495c035a-68f7-42a1-b2a9-28b89ee01d6b` | `5d3ad276618bc01bae27b6b43a83e978` | 陈加恩 | 2026-05 | `2c2f34a3-f553-4d11-b1e4-d92c553fbb0c` | `6db58942-7b98-4cb1-aa3d-c40b199e54c5` | `121d84e6-fc9f-4d47-bd8f-6a3cee096a16` | `5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1` | `ab027f173099b22536eb6c4edb73268a` |
| 2 | `747398ab-db47-493a-8047-4da69174e32b` | `f9fe1a977a030e519db136cf153bfb9b` | 陈加恩 | 2026-05 | `002875ac-4b12-4f83-b752-d5972d8bb7fa` | `6db58942-7b98-4cb1-aa3d-c40b199e54c5` | `121d84e6-fc9f-4d47-bd8f-6a3cee096a16` | `5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1` | `77f932de5a1f4948ece4dee63344b74d` |
| 3 | `8dce41c6-9df0-45e0-bd19-46aeb5fffedc` | `8645bf1604c52df8438e31a6c1d5fb78` | 陈加恩 | 2026-05 | `511d1cfd-b570-4ee0-a827-9fbec8768743` | `6db58942-7b98-4cb1-aa3d-c40b199e54c5` | `121d84e6-fc9f-4d47-bd8f-6a3cee096a16` | `5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1` | `fc69b063c6adcff5daa1241c4fbbbb3a` |
| 4 | `8e778948-194f-40a0-9c6f-cfa3d8637c22` | `ebddcfc08659025b0011e1a7939bc58b` | 陈加恩 | 2026-05 | `7209bf5d-1916-4f61-bb4c-41dd0b667028` | `6db58942-7b98-4cb1-aa3d-c40b199e54c5` | `121d84e6-fc9f-4d47-bd8f-6a3cee096a16` | `5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1` | `d2ec92c9952ad1468ea76a7833892933` |
| 5 | `94e720de-0715-442f-a32a-848a31af3440` | `ace9d0e97b6dff47bc066f9c8ece3bec` | 陈加恩 | 2026-05 | `daa403bd-4c8b-4752-a1a6-717c9270f661` | `6db58942-7b98-4cb1-aa3d-c40b199e54c5` | `121d84e6-fc9f-4d47-bd8f-6a3cee096a16` | `5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1` | `03d32132cd4c5ffeee63c9c18d110d6c` |
| 6 | `a25f02e1-1855-40e6-823d-93789a9ddea7` | `c26b1fb170e7c027da17368b509e9414` | 陈加恩 | 2026-05 | `4459aef2-735a-42bb-882d-e473571398cf` | `6db58942-7b98-4cb1-aa3d-c40b199e54c5` | `121d84e6-fc9f-4d47-bd8f-6a3cee096a16` | `5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1` | `462a681344ec346e3d46dfa6ed71e871` |
| 7 | `dd5a4236-f236-4c41-bbb8-84e1907531db` | `b9b96d7152e7d5b4a5a8d532f4639001` | 陈加恩 | 2026-05 | `d14ea4da-743a-41f6-8203-cea07f59cfb7` | `6db58942-7b98-4cb1-aa3d-c40b199e54c5` | `121d84e6-fc9f-4d47-bd8f-6a3cee096a16` | `5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1` | `ab4973e72027cd86c8e9e04e5fa5e771` |
| 8 | `ed2b7a74-6f6e-4448-8d84-c610754dfb8f` | `bbda62e926307d064dab6716c37b9c26` | 陈加恩 | 2026-05 | `b2967413-882f-416f-b038-be8520e934a7` | `6db58942-7b98-4cb1-aa3d-c40b199e54c5` | `121d84e6-fc9f-4d47-bd8f-6a3cee096a16` | `5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1` | `bfde93b7cbf347135bb05411e2bdd2e4` |
| 9 | `ef7e9696-f655-4b0f-b627-cc51975e6515` | `dfe00f02fdf6128365ac163438061ba6` | 陈加恩 | 2026-05 | `d53292ea-74c0-43ec-9b94-a4d22a0acaf4` | `6db58942-7b98-4cb1-aa3d-c40b199e54c5` | `121d84e6-fc9f-4d47-bd8f-6a3cee096a16` | `5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1` | `a2c6783aae17babbab3a9185a27254fd` |
| 10 | `fddeae0d-47b6-4e4b-9f6b-ade92d3de922` | `5e2a2aa03a1ea38ea64360865a3f6668` | 陈加恩 | 2026-05 | `2fc6bac6-7324-4bef-ad5d-a25ffcefb168` | `6db58942-7b98-4cb1-aa3d-c40b199e54c5` | `121d84e6-fc9f-4d47-bd8f-6a3cee096a16` | `5b32387d-7dc0-4c96-adf5-eaf1b10c1ff1` | `50fe1695e7fee1def843bed90b90a929` |
| 11 | `200cfd39-f61f-4ac4-9f0e-5cc3d885f670` | `3ac1a3f26dacdcce8cfc764674ddf013` | 陈红卓 | 2026-05 | `62735cb7-bddc-4b96-bd16-ba74842c7c47` | `64ae8e85-0edb-468b-8310-1e1d396104e9` | `18a80ecd-4486-44d6-95ca-324d2030404f` | `dba70bdc-f6a0-4bbc-ae63-bd1f69837457` | `b057a252bf3ede3077ed3c64bc051428` |
| 12 | `2852a46d-9d9d-4db6-8247-df3cc50725d8` | `af036483cc8ed66939bf37d2ee3af1ea` | 陈红卓 | 2026-05 | `c60bdbe6-9bcf-4f6a-8bc4-333ac027ede9` | `64ae8e85-0edb-468b-8310-1e1d396104e9` | `18a80ecd-4486-44d6-95ca-324d2030404f` | `dba70bdc-f6a0-4bbc-ae63-bd1f69837457` | `40c87fe0f28b4f6d4e8904265b53163e` |
| 13 | `4724f45b-c66c-4ae2-b4ab-a1f06e0d545f` | `1ca747eb81bab16875f524c75798210c` | 陈红卓 | 2026-05 | `a6bc3f1e-717e-4933-89b9-efb8e956726d` | `64ae8e85-0edb-468b-8310-1e1d396104e9` | `18a80ecd-4486-44d6-95ca-324d2030404f` | `dba70bdc-f6a0-4bbc-ae63-bd1f69837457` | `0e21f1a0796608eed919fe209f0d2a67` |
| 14 | `606d7dfe-3eb6-4884-a0c6-75a1ccc8e335` | `094ad9e4c6b583beeb36a2bc856296e0` | 陈红卓 | 2026-05 | `8cd37bd7-cfeb-482c-90f9-4a74144d658b` | `64ae8e85-0edb-468b-8310-1e1d396104e9` | `18a80ecd-4486-44d6-95ca-324d2030404f` | `dba70bdc-f6a0-4bbc-ae63-bd1f69837457` | `865910b9f721492c7fb10f273540b5e1` |
| 15 | `ada45346-50cd-41ce-9568-71d8bb1038a1` | `1f136ac621568d18a5c5174969f578b1` | 陈红卓 | 2026-05 | `b675f59e-edbd-4cdd-a001-b081375439a3` | `64ae8e85-0edb-468b-8310-1e1d396104e9` | `18a80ecd-4486-44d6-95ca-324d2030404f` | `dba70bdc-f6a0-4bbc-ae63-bd1f69837457` | `224928ef89ad740376016185db7a8bd8` |
| 16 | `cc24c61f-91d7-49d8-bbfc-73e13e4e7841` | `4637b1df60bd0b36f9fded098cb20a19` | 陈红卓 | 2026-05 | `e34a3a1f-83b4-4776-81b4-ef8f8165436e` | `64ae8e85-0edb-468b-8310-1e1d396104e9` | `18a80ecd-4486-44d6-95ca-324d2030404f` | `dba70bdc-f6a0-4bbc-ae63-bd1f69837457` | `28ca3351359d79139838b83b789b352d` |
| 17 | `cdebfb82-e551-4598-bfc5-70e540f438e8` | `dc459956de00a1d6a40255cd91e581a1` | 陈红卓 | 2026-05 | `c79b2cce-4372-4720-a565-995e18e7c318` | `64ae8e85-0edb-468b-8310-1e1d396104e9` | `18a80ecd-4486-44d6-95ca-324d2030404f` | `dba70bdc-f6a0-4bbc-ae63-bd1f69837457` | `787dff73f5917bacaa58e3939dfc1eb2` |
| 18 | `e4ac1818-4d2f-4f3f-8979-65ab934f64fc` | `2932d2a64f095f6c7485f549a51a3541` | 陈红卓 | 2026-05 | `ff6f9dd7-5b6c-4f47-90e9-9531f72e4ca3` | `64ae8e85-0edb-468b-8310-1e1d396104e9` | `18a80ecd-4486-44d6-95ca-324d2030404f` | `dba70bdc-f6a0-4bbc-ae63-bd1f69837457` | `f32adf79910bbb0503c785994aa94779` |
| 19 | `f99c2359-d9de-4603-a6ed-5b173b94d150` | `9c6462008676151f4325d3f150527422` | 陈红卓 | 2026-05 | `e0ce2693-0d38-4018-90a2-e8a78de2774f` | `64ae8e85-0edb-468b-8310-1e1d396104e9` | `18a80ecd-4486-44d6-95ca-324d2030404f` | `dba70bdc-f6a0-4bbc-ae63-bd1f69837457` | `2ca2030d9b531e19bc9c7446f0ba267f` |
| 20 | `ff1f1f7e-671f-48db-885e-14d0a808caed` | `4a68f6108d276eb01a1e735d6a8e203a` | 陈红卓 | 2026-05 | `4818624b-9302-446d-8982-c5ed09a9f50f` | `64ae8e85-0edb-468b-8310-1e1d396104e9` | `18a80ecd-4486-44d6-95ca-324d2030404f` | `dba70bdc-f6a0-4bbc-ae63-bd1f69837457` | `21a95d17b396c48ef81137201116e662` |
| 21 | `05246e13-b353-428b-a5cc-2da1cf4e903a` | `00634dd5baea89050eb7aaf82b7f2dfc` | 陈加恩 | 2026-06 | `bf9d3520-1a31-4605-bb17-e1eda5ef89a3` | `24c9f706-6eb8-4592-80d2-18446ca6ba42` | `3176d629-f319-497a-95ae-2366a43cdf7a` | `fd90b997-d31d-4553-bda3-a9cc2096c404` | `58e7c84bd7d4756e89c9b62c093daae4` |
| 22 | `0aa5af82-783c-4164-b0a1-1ee1289e7d71` | `9490438221f5184ec7500f53e3d8d12f` | 陈加恩 | 2026-06 | `a2eb187e-d3ec-464b-9710-b0a63db6ab10` | `24c9f706-6eb8-4592-80d2-18446ca6ba42` | `3176d629-f319-497a-95ae-2366a43cdf7a` | `fd90b997-d31d-4553-bda3-a9cc2096c404` | `217d9b2d112de6532d1f59cde0d137f1` |
| 23 | `1309c4cc-8abc-43ae-bde9-c7a9634a5aca` | `b0a8da4de95646f50771edcb1435a3c4` | 陈加恩 | 2026-06 | `7bb82294-33ba-4f28-b19d-d63623c5e659` | `24c9f706-6eb8-4592-80d2-18446ca6ba42` | `3176d629-f319-497a-95ae-2366a43cdf7a` | `fd90b997-d31d-4553-bda3-a9cc2096c404` | `6ad46d5bead5416e333001007b8e5341` |
| 24 | `2ed4a45c-423f-4eb6-8dcf-ae99a2d78e8a` | `f640eacc94ff817604d944b3fade8ef2` | 陈加恩 | 2026-06 | `6f0d528b-f414-4632-814e-d965b1f2960e` | `24c9f706-6eb8-4592-80d2-18446ca6ba42` | `3176d629-f319-497a-95ae-2366a43cdf7a` | `fd90b997-d31d-4553-bda3-a9cc2096c404` | `2bc73f067629eda052bec091dd9666e5` |
| 25 | `50d2aeee-538d-4582-8a3c-5fb692cd9f07` | `f78e435fe7970e3c68468fcbb0d426f1` | 陈加恩 | 2026-06 | `4c974e87-3d7b-44ee-8a73-53149e3d9a8e` | `24c9f706-6eb8-4592-80d2-18446ca6ba42` | `3176d629-f319-497a-95ae-2366a43cdf7a` | `fd90b997-d31d-4553-bda3-a9cc2096c404` | `773dc32b89f50888c4255165b333b221` |
| 26 | `b1d25f4b-d95b-4a39-8e87-2bc9a0382b6b` | `529eb5bd838376040b4b2d0af1544315` | 陈加恩 | 2026-06 | `f29301e0-4e8a-46c8-8cd6-21edd16409e2` | `24c9f706-6eb8-4592-80d2-18446ca6ba42` | `3176d629-f319-497a-95ae-2366a43cdf7a` | `fd90b997-d31d-4553-bda3-a9cc2096c404` | `f9f9620735a9f7c21a323e49bdc27e16` |
| 27 | `b53d5c38-edcf-4e5c-ac38-286030abef81` | `ef6e38d4bffacc60af9f484ac4f92528` | 陈加恩 | 2026-06 | `34e930c9-63cd-4b91-a027-0d5a7ea16517` | `24c9f706-6eb8-4592-80d2-18446ca6ba42` | `3176d629-f319-497a-95ae-2366a43cdf7a` | `fd90b997-d31d-4553-bda3-a9cc2096c404` | `fa8a16544c46815aa0399a9febd950b8` |
| 28 | `cf3236a0-21f5-4fd3-8622-42a20aa19ebd` | `b6f95f21e49bb3baa3665902a1484b26` | 陈加恩 | 2026-06 | `1c93d2be-c0c6-4e0b-a220-b7df04ab18ed` | `24c9f706-6eb8-4592-80d2-18446ca6ba42` | `3176d629-f319-497a-95ae-2366a43cdf7a` | `fd90b997-d31d-4553-bda3-a9cc2096c404` | `555c02f1552a7684df9fe7eb739d6ae7` |
| 29 | `e131726d-b55d-4795-aeff-6fdf966b5017` | `b19ac2cafe2121c7342917190cf724d4` | 陈加恩 | 2026-06 | `ccac353f-d4b6-4698-ad4f-288e6cf7c613` | `24c9f706-6eb8-4592-80d2-18446ca6ba42` | `3176d629-f319-497a-95ae-2366a43cdf7a` | `fd90b997-d31d-4553-bda3-a9cc2096c404` | `3fada3574592978db2f6368a729fc5d7` |
| 30 | `e3d729b4-4aab-480a-b574-cb02dae0ec71` | `f055310406a7b05f983598e0f2d3a97f` | 陈加恩 | 2026-06 | `8112c37e-fc63-4b2b-b4a2-25ee241a143c` | `24c9f706-6eb8-4592-80d2-18446ca6ba42` | `3176d629-f319-497a-95ae-2366a43cdf7a` | `fd90b997-d31d-4553-bda3-a9cc2096c404` | `4a4e9b5dcb916830697eab83f99282ae` |
| 31 | `e85b6f77-87ae-42bd-bef4-60ebf4d307d0` | `412b0d286b8fd53ed0902a9ec73d748a` | 陈加恩 | 2026-06 | `1a951d5f-030b-4656-929e-36426646b1d5` | `24c9f706-6eb8-4592-80d2-18446ca6ba42` | `3176d629-f319-497a-95ae-2366a43cdf7a` | `fd90b997-d31d-4553-bda3-a9cc2096c404` | `90f6344d0145dd8cb9709bc022d918d7` |
| 32 | `faed40b8-a819-4224-8da1-6e463dde4de7` | `947e35d6efb510baf06c184e081f3e05` | 陈加恩 | 2026-06 | `c6533183-1553-46f1-bbf6-7e2508383d81` | `24c9f706-6eb8-4592-80d2-18446ca6ba42` | `3176d629-f319-497a-95ae-2366a43cdf7a` | `fd90b997-d31d-4553-bda3-a9cc2096c404` | `e6f91fe9a90a631e0adab74f3aeb07a0` |
| 33 | `1f767cd5-a265-4c4a-8b99-58f0e0ad4c09` | `218ee1cca4735749e499f5a1207798a9` | 陈红卓 | 2026-06 | `bc924326-5913-4902-9169-690f34b11df8` | `bffa9c9f-27d7-4522-93ed-d64ff629513a` | `365a26cb-2c25-4b0b-b34b-01bba26c766c` | `bb124b53-ab20-4c85-aad2-a83bc316132d` | `64f5099af2f7439c648d0e871d69fe98` |
| 34 | `2def09c2-b6ac-4b5d-bbd1-5b1b7fee6037` | `fee3f05ad997a6cd944be6683207c319` | 陈红卓 | 2026-06 | `e7b2eb2c-a974-425b-8e0e-175e797e8601` | `bffa9c9f-27d7-4522-93ed-d64ff629513a` | `365a26cb-2c25-4b0b-b34b-01bba26c766c` | `bb124b53-ab20-4c85-aad2-a83bc316132d` | `a893d73c57144e7c0e2f5f6f6cd989d7` |
| 35 | `458017c5-ab50-44c8-a304-8851a73b3ce3` | `16f6fad84f976476e8ed75a7d730431e` | 陈红卓 | 2026-06 | `aefaa674-9fe4-4874-bf35-e97c8e2c89dc` | `bffa9c9f-27d7-4522-93ed-d64ff629513a` | `365a26cb-2c25-4b0b-b34b-01bba26c766c` | `bb124b53-ab20-4c85-aad2-a83bc316132d` | `012474619190fc41b663012abdc6f09f` |
| 36 | `632a3bb3-1ebb-4941-9e22-98c07d829695` | `a95c00ea2914f1180bdcdd6a298e491e` | 陈红卓 | 2026-06 | `c5298639-038d-4b89-9df4-974367ab7c0c` | `bffa9c9f-27d7-4522-93ed-d64ff629513a` | `365a26cb-2c25-4b0b-b34b-01bba26c766c` | `bb124b53-ab20-4c85-aad2-a83bc316132d` | `0ec1875296531416c0d32b9cceac4fae` |
| 37 | `79356de1-f6cb-4d80-811c-9e78c5b3672d` | `0cfe12d96227e538431d2ea07b6757e7` | 陈红卓 | 2026-06 | `fbbd5dc8-294a-4cfb-967a-6f27ad97391f` | `bffa9c9f-27d7-4522-93ed-d64ff629513a` | `365a26cb-2c25-4b0b-b34b-01bba26c766c` | `bb124b53-ab20-4c85-aad2-a83bc316132d` | `520926b164318cb92cf064c3c2e57946` |
| 38 | `7e5730ec-ad51-4f8b-87a6-c4cc225b6ede` | `c581ebfc9cbefd0ec01304ff9ae0532f` | 陈红卓 | 2026-06 | `05451028-ecdb-41d2-8077-baf8e1ad3e97` | `bffa9c9f-27d7-4522-93ed-d64ff629513a` | `365a26cb-2c25-4b0b-b34b-01bba26c766c` | `bb124b53-ab20-4c85-aad2-a83bc316132d` | `879293d0353a04b43916eb48ac620aa1` |
| 39 | `a4316220-13aa-486d-8262-f20d4de6a436` | `0c251281cf06743de80f4ada86be1f03` | 陈红卓 | 2026-06 | `90cd07c4-4b18-43ec-a6c2-c7ed46988cd6` | `bffa9c9f-27d7-4522-93ed-d64ff629513a` | `365a26cb-2c25-4b0b-b34b-01bba26c766c` | `bb124b53-ab20-4c85-aad2-a83bc316132d` | `184da0d3e1382c71b376c5a343fe34e1` |
| 40 | `d722a147-6ada-44e6-8caf-85bf09e8af3c` | `7e885c1d2cde3a5cb5fb3b60d5e0a2ad` | 陈红卓 | 2026-06 | `f9b85a6f-36ae-4f57-b1a6-8d630bece00b` | `bffa9c9f-27d7-4522-93ed-d64ff629513a` | `365a26cb-2c25-4b0b-b34b-01bba26c766c` | `bb124b53-ab20-4c85-aad2-a83bc316132d` | `692b50a0042c7702b6aa0a7a8606d870` |
| 41 | `dbadbee8-b460-4671-ac16-44021cbe599b` | `8864b522f4c3fdc326212f3513506e0e` | 陈红卓 | 2026-06 | `1cbeb207-ca6d-48bf-b6a5-f89b6ecc8687` | `bffa9c9f-27d7-4522-93ed-d64ff629513a` | `365a26cb-2c25-4b0b-b34b-01bba26c766c` | `bb124b53-ab20-4c85-aad2-a83bc316132d` | `a7fa64a41493445208822092e3cf4bd7` |
| 42 | `ee682a14-dbea-4480-966a-34fafb9b5902` | `46172777e57e72d4d3b6e5d40447d588` | 陈红卓 | 2026-06 | `840d3f42-dbd2-408c-8ecd-b9a89fa74411` | `bffa9c9f-27d7-4522-93ed-d64ff629513a` | `365a26cb-2c25-4b0b-b34b-01bba26c766c` | `bb124b53-ab20-4c85-aad2-a83bc316132d` | `0f9d4cb4541b850d8784be2c2d09fb5c` |

## 4. 业务审批边界

业务负责人已正式批准Manifest B，批准语义为：

- 认可上述固定42 UUID已经包含在对应学生/月/业务归属的历史月度收费与收款事实中；
- 允许未来candidate规则把这42条作为已结算历史排除；
- 承认旧系统没有lesson级immutable snapshot，本批准是对固定月度证据的业务归属确认。
- 确认四笔JPY204,000收入覆盖对应月份全部planned课程，包含后来进入`pending_makeup`的6条课程。

该批准不能：

- 动态扩展到同学生同月的其他lesson；
- 动态扩展到同业务归属或其他lesson，或处理6条`pending_makeup`；
- 补造历史tuition bill、bill relation、identity或月结lesson snapshot；
- 自动决定billing month/week、student settlement字段或decided_at；
- 回填42条的新收费归属字段，或直接授权candidate函数修改、candidate切换或R0 gate解除。

后续实施必须另开独立阶段，建立不可变排除证据并经过rollback、postdeploy和Git审查。在该阶段获批并完成前，继续保持当前160条集合和R0 gate。
