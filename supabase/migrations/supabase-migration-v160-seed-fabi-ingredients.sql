-- v160 — Seed Fabi's ingredient table. One row per thing he actually eats.
--
-- This is deliberately NOT a food database. It is ~40 decided rows for one
-- person, so "which brand of noodles / ham / cheese" stops being a question he
-- has to answer at every meal. German supermarket values, EU per-100 g basis.
--
-- weight_basis matters: raw/dry means weigh it BEFORE cooking, which is both
-- easier (it is loose in the pack) and more accurate (no water-loss guessing).
-- Calories and protein survive the pan; water does not.
--
-- Alcohol rows carry alcohol_100 in grams so the Widmark model and the drunk
-- detector get a real input instead of a flat 100 kcal "Cocktail" placeholder.
-- alcohol_g = abv% * 0.789; kcal ~= 7*alcohol_g + 4*carbs_g.
--
-- Re-runnable: ON CONFLICT updates in place, so tuning a value is just an edit
-- and a re-apply.

INSERT INTO public.food_ingredients
  (user_id, key, name, name_local, kcal_100, protein_100, fat_100, carbs_100,
   alcohol_100, nova_class, mind_tags, default_grams, unit_hint, weight_basis)
SELECT u.id, v.key, v.name, v.name_local, v.kcal, v.pro, v.fat, v.carb,
       v.alc, v.nova, v.tags, v.def, v.hint, v.basis
FROM (SELECT '372210e5-1dda-41b3-b759-5ff72293b8ff'::uuid AS id) u,
(VALUES
  -- ---- protein -----------------------------------------------------------
  ('chicken_breast','Chicken breast','Hähnchenbrustfilet',106,23.1,1.9,0,0,1,ARRAY['poultry','lean_protein'],250,'weigh raw','raw'),
  ('chicken_thigh','Chicken thigh','Hähnchenschenkel',185,18.5,12.0,0,0,1,ARRAY['poultry'],200,'weigh raw','raw'),
  ('pork_schnitzel','Pork schnitzel','Schweineschnitzel',143,21.5,6.0,0,0,1,ARRAY['red_meat'],180,'weigh raw','raw'),
  ('hackfleisch','Ground meat, mixed','Hackfleisch gemischt',240,18.0,18.5,0,0,1,ARRAY['red_meat'],250,'weigh raw','raw'),
  ('beef_liver','Beef liver','Rinderleber',130,20.0,3.8,3.5,0,1,ARRAY['organ_meat'],235,'weigh raw','raw'),
  ('bratwurst','Bratwurst, butcher','Bratwurst',300,11.8,27.0,0.7,0,2,ARRAY['red_meat','processed_meat'],110,'1 sausage ≈ 110 g','raw'),
  ('kochschinken','Cooked ham','Kochschinken',110,18.0,3.2,1.0,0,4,ARRAY['processed_meat'],100,NULL,'ready'),
  ('salmon','Salmon fillet','Lachsfilet',208,20.0,13.0,0,0,1,ARRAY['fish','omega3'],180,'weigh raw','raw'),
  ('egg','Egg','Ei',143,12.6,9.9,0.7,0,1,ARRAY['egg'],60,'1 egg ≈ 60 g','raw'),
  ('whey','Whey protein','Whey Protein',380,80.0,5.0,6.0,0,4,ARRAY['supplement'],30,'1 scoop ≈ 30 g','dry'),
  -- ---- dairy -------------------------------------------------------------
  ('cheddar','Cheddar','Cheddar',410,25.0,34.0,1.3,0,4,ARRAY['cheese','sat_fat'],50,NULL,'ready'),
  ('cheese_mix','Gouda / cheese mix','Käsemischung',356,25.0,27.4,0,0,4,ARRAY['cheese','sat_fat'],50,NULL,'ready'),
  ('quark_mager','Quark, lean','Magerquark',67,12.0,0.3,4.1,0,1,ARRAY['dairy','lean_protein'],250,NULL,'ready'),
  ('skyr','Skyr','Skyr',63,11.0,0.2,4.0,0,1,ARRAY['dairy','lean_protein'],150,NULL,'ready'),
  ('milk','Milk 3.5%','Vollmilch',64,3.3,3.5,4.7,0,1,ARRAY['dairy'],200,'ml ≈ g','liquid'),
  ('butter','Butter','Butter',741,0.7,82.0,0.6,0,2,ARRAY['added_fat','sat_fat'],10,NULL,'ready'),
  -- ---- carbs -------------------------------------------------------------
  ('rice_white','White rice','Reis',360,7.1,0.7,79.0,0,1,ARRAY['refined_grains'],90,'weigh dry','dry'),
  ('fusilli','Fusilli','Fusilli',360,12.0,1.5,72.0,0,3,ARRAY['refined_grains'],125,'weigh dry','dry'),
  ('potato','Potato','Kartoffel',77,2.0,0.1,17.0,0,1,ARRAY['vegetable'],300,'weigh raw','raw'),
  ('oats','Oats','Haferflocken',370,13.5,7.0,59.0,0,1,ARRAY['whole_grains'],80,'weigh dry','dry'),
  ('kaisersemmel','Kaiser roll','Kaisersemmel',280,9.5,2.6,54.0,0,3,ARRAY['refined_grains'],57,'1 roll ≈ 57 g','ready'),
  ('baguette','Baguette','Baguette',270,9.0,1.5,55.0,0,3,ARRAY['refined_grains'],125,'half ≈ 125 g','ready'),
  ('bread_whole','Wholegrain bread','Vollkornbrot',220,7.5,3.3,38.0,0,3,ARRAY['whole_grains'],50,'1 slice ≈ 50 g','ready'),
  ('toast_bread','Toast bread','Toastbrot',270,8.5,4.0,48.0,0,4,ARRAY['refined_grains'],25,'1 slice ≈ 25 g','ready'),
  -- ---- fats + extras -----------------------------------------------------
  ('olive_oil','Olive oil','Olivenöl',884,0,100.0,0,0,2,ARRAY['added_fat','olive_oil'],10,'1 tbsp ≈ 13 g','ready'),
  ('rapeseed_oil','Rapeseed oil','Rapsöl',884,0,100.0,0,0,2,ARRAY['added_fat'],10,'1 tbsp ≈ 13 g','ready'),
  ('ketchup','Ketchup','Ketchup',110,1.2,0.1,25.0,0,4,ARRAY['added_sugar'],20,NULL,'ready'),
  ('onion','Onion','Zwiebel',40,1.1,0.1,9.3,0,1,ARRAY['vegetable'],110,'1 onion ≈ 110 g','raw'),
  ('garlic','Garlic','Knoblauch',149,6.4,0.5,33.0,0,1,ARRAY['vegetable'],5,'1 clove ≈ 5 g','raw'),
  ('passata','Tomato passata','Passata',35,1.5,0.2,6.0,0,3,ARRAY['vegetable'],200,NULL,'ready'),
  ('banana','Banana','Banane',89,1.1,0.3,23.0,0,1,ARRAY['fruit'],118,'1 banana ≈ 118 g','ready'),
  ('apple','Apple','Apfel',52,0.3,0.2,14.0,0,1,ARRAY['fruit'],180,'1 apple ≈ 180 g','ready'),
  -- ---- alcohol (per 100 ml) ----------------------------------------------
  ('beer_pils','Beer, Pils','Bier',42,0.5,0,3.3,3.9,3,ARRAY['alcohol'],500,'0.5 L ≈ 500 ml','liquid'),
  ('wine_white','White wine','Weißwein',78,0.1,0,2.6,9.5,3,ARRAY['alcohol'],150,'1 glass ≈ 150 ml','liquid'),
  ('wine_red','Red wine','Rotwein',82,0.1,0,2.6,10.0,3,ARRAY['alcohol'],150,'1 glass ≈ 150 ml','liquid'),
  ('aperol_spritz','Aperol Spritz','Aperol Spritz',90,0,0,11.0,6.3,4,ARRAY['alcohol','added_sugar'],200,'1 glass ≈ 200 ml','liquid'),
  ('gin_tonic','Gin & Tonic','Gin Tonic',75,0,0,7.0,6.3,4,ARRAY['alcohol','added_sugar'],250,'1 longdrink ≈ 250 ml','liquid'),
  ('spirit_40','Spirit 40%','Schnaps 40%',224,0,0,0,31.6,3,ARRAY['alcohol'],40,'1 shot ≈ 40 ml','liquid'),
  ('cocktail_sweet','Cocktail, sweet','Cocktail',120,0,0,14.0,9.0,4,ARRAY['alcohol','added_sugar'],250,'1 cocktail ≈ 250 ml','liquid')
) AS v(key,name,name_local,kcal,pro,fat,carb,alc,nova,tags,def,hint,basis)
ON CONFLICT (user_id, key) DO UPDATE SET
  name = excluded.name, name_local = excluded.name_local,
  kcal_100 = excluded.kcal_100, protein_100 = excluded.protein_100,
  fat_100 = excluded.fat_100, carbs_100 = excluded.carbs_100,
  alcohol_100 = excluded.alcohol_100, nova_class = excluded.nova_class,
  mind_tags = excluded.mind_tags, default_grams = excluded.default_grams,
  unit_hint = excluded.unit_hint, weight_basis = excluded.weight_basis;
