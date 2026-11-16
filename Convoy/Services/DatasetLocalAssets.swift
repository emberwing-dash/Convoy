import Foundation

enum DatasetLocalAssets {
    static let nameToAsset: [String: String] = [
        "Hero Passion X-Pro 2018": "dataset_hero_passion_x_pro_2018",
        "Hero Xpulse 200 2019": "dataset_hero_xpulse_200_2019",
        "Hero Xpulse 200 4V 2021": "dataset_hero_xpulse_200_4v_2021",
        "Hero Xpulse 200T 2019": "dataset_hero_xpulse_200t_2019",
        "Hero Xtreme 160R 2020": "dataset_hero_xtreme_160r_2020",
        "Hero Xtreme 200R 2018": "dataset_hero_xtreme_200r_2018",
        "Hero Xtreme Sports 2015": "dataset_hero_xtreme_sports_2015",
        "Honda Africa Twin 2022 Adventure Sport DCT": "dataset_honda_africa_twin_2022_adventure_sport_dct",
        "Honda CB300F 2022 DLX PRO": "dataset_honda_cb300f_2022_dlx_pro",
        "Honda CB300R 2022 STD": "dataset_honda_cb300r_2022_std",
        "Honda CB650R 2022 STD": "dataset_honda_cb650r_2022_std",
        "Honda CBR650R 2022 STD": "dataset_honda_cbr650r_2022_std",
        "Royal Enfield Bullet 2013": "dataset_royal_enfield_bullet_2013",
        "Royal Enfield Classic 350 2021": "dataset_royal_enfield_classic_350_2021",
        "Royal Enfield Continental GT 650 2018": "dataset_royal_enfield_continental_gt_650_2018",
        "Royal Enfield Himalayan 2021": "dataset_royal_enfield_himalayan_2021",
        "Royal Enfield Hunter 350 2022": "dataset_royal_enfield_hunter_350_2022",
        "Royal Enfield Meteor 350 2020": "dataset_royal_enfield_meteor_350_2020",
        "Royal Enfield Thunderbird 350X 2018": "dataset_royal_enfield_thunderbird_350x_2018",
        "Suzuki GSX-S750 2018": "dataset_suzuki_gsx_s750_2018",
        "Suzuki Gixxer 2020": "dataset_suzuki_gixxer_2020",
        "Suzuki Gixxer 250 2020": "dataset_suzuki_gixxer_250_2020",
        "Suzuki Gixxer SF 2020": "dataset_suzuki_gixxer_sf_2020",
        "Suzuki Intruder 150 2020": "dataset_suzuki_intruder_150_2020",
        "Suzuki Katana 2022": "dataset_suzuki_katana_2022",
        "Suzuki V-Strom SX 2022": "dataset_suzuki_v_strom_sx_2022",
        "TVS Apache RTR 160 2020": "dataset_tvs_apache_rtr_160_2020",
        "TVS Apache RTR 180 2020": "dataset_tvs_apache_rtr_180_2020",
        "TVS Apache RTR 200 2019": "dataset_tvs_apache_rtr_200_2019",
        "TVS Apache RTR 200 4V 2020": "dataset_tvs_apache_rtr_200_4v_2020",
        "TVS Radeon 2020": "dataset_tvs_radeon_2020",
        "Yamaha FZ 2020": "dataset_yamaha_fz_2020",
        "Yamaha FZ 25 2019": "dataset_yamaha_fz_25_2019",
        "Yamaha FZ-X 2021": "dataset_yamaha_fz_x_2021",
        "Yamaha Fazer 2019": "dataset_yamaha_fazer_2019",
        "Yamaha MT-09 2018": "dataset_yamaha_mt_09_2018",
        "Yamaha Saluto 125 2019": "dataset_yamaha_saluto_125_2019",
        "Yamaha XSR 900 2018": "dataset_yamaha_xsr_900_2018",
        "Yamaha YZF-R1 2018": "dataset_yamaha_yzf_r1_2018",
        "Yamaha YZF-R15 V3.0 2020": "dataset_yamaha_yzf_r15_v3_0_2020",
    ]

    static func assetName(for bikeName: String) -> String? {
        if let direct = nameToAsset[bikeName] { return direct }
        let clean = bikeName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for (k, v) in nameToAsset {
            if k.lowercased() == clean || clean.contains(k.lowercased()) || k.lowercased().contains(clean) {
                return v
            }
        }
        return nil
    }

    static func assetName(make: String, model: String) -> String? {
        let combined = "\(make) \(model)"
        return assetName(for: combined)
    }
}
