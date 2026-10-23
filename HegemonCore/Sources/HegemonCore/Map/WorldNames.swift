/// Names for generated worlds: lands with their peoples and rulers, tribal homelands, and seas.
/// Drawn from the Late Bronze Age and its edges, placed by climate, so a random world reads like
/// the age even though its coasts are new.
enum WorldNames {
    /// Where a name sits best: cold north, warm coasts and plains, dry south, islands, highlands.
    enum Climate { case cold, warm, dry, sea, high }

    struct Land {
        let land: String
        let people: String
        let ruler: String
        let temperament: Temperament
        let look: String
        let climate: Climate
    }

    static let lands: [Land] = [
        // The classic board's peoples.
        Land(land: "Hibernia", people: "the Hibernians", ruler: "Eber", temperament: .peaceable, look: "north", climate: .cold),
        Land(land: "Britain", people: "the Britons", ruler: "Bran", temperament: .mercantile, look: "north", climate: .cold),
        Land(land: "Sitones", people: "the Sitones", ruler: "Hrodulf", temperament: .peaceable, look: "north", climate: .cold),
        Land(land: "Saxone", people: "the Saxons", ruler: "Hengist", temperament: .warlike, look: "north", climate: .cold),
        Land(land: "Gaul", people: "the Gauls", ruler: "Ambigatus", temperament: .warlike, look: "north", climate: .cold),
        Land(land: "Hispania", people: "the Iberians", ruler: "Indibil", temperament: .proud, look: "chief", climate: .high),
        Land(land: "Pyrenees", people: "the Vascones", ruler: "Aitor", temperament: .proud, look: "chief", climate: .high),
        Land(land: "Baetica", people: "Tartessos", ruler: "Arganthonios", temperament: .mercantile, look: "chief", climate: .warm),
        Land(land: "Alps", people: "the Raeti", ruler: "Raetus", temperament: .proud, look: "north", climate: .high),
        Land(land: "Sardinia", people: "the Sherden", ruler: "Sardus", temperament: .warlike, look: "chief", climate: .sea),
        Land(land: "Sicilia", people: "the Sicels", ruler: "Siculus", temperament: .peaceable, look: "chief", climate: .sea),
        Land(land: "Macedonia", people: "the Macedones", ruler: "Karanos", temperament: .warlike, look: "greece", climate: .high),
        Land(land: "Crete", people: "Knossos", ruler: "Idomeneus", temperament: .mercantile, look: "greece", climate: .sea),
        Land(land: "Dacia", people: "the Getae", ruler: "Zalmoxis", temperament: .proud, look: "north", climate: .cold),
        Land(land: "Thrace", people: "the Thracians", ruler: "Rhesus", temperament: .warlike, look: "north", climate: .warm),
        Land(land: "Caucasus", people: "the Colchians", ruler: "Aeetes", temperament: .proud, look: "hatti", climate: .high),
        Land(land: "Armenia", people: "Nairi", ruler: "Arame", temperament: .proud, look: "mesopotamia", climate: .high),
        Land(land: "Media", people: "the Medes", ruler: "Deioces", temperament: .warlike, look: "mesopotamia", climate: .high),
        Land(land: "Persia", people: "Elam", ruler: "Shutruk-Nakhunte", temperament: .proud, look: "mesopotamia", climate: .dry),
        Land(land: "Taurus", people: "the Lukka", ruler: "Piyama-Radu", temperament: .warlike, look: "hatti", climate: .high),
        Land(land: "Anatolia", people: "Hatti", ruler: "Suppiluliuma II", temperament: .proud, look: "hatti", climate: .warm),
        Land(land: "Cyprus", people: "Alashiya", ruler: "Kushmeshusha", temperament: .mercantile, look: "greece", climate: .sea),
        Land(land: "Syria", people: "Ugarit", ruler: "Ammurapi", temperament: .mercantile, look: "mesopotamia", climate: .warm),
        Land(land: "Petraea", people: "the Shasu", ruler: "Seir", temperament: .warlike, look: "chief", climate: .dry),
        Land(land: "Libya", people: "the Libu", ruler: "Meryey", temperament: .warlike, look: "libyan", climate: .dry),
        Land(land: "Cyrenaica", people: "the Meshwesh", ruler: "Mesher", temperament: .warlike, look: "libyan", climate: .dry),
        Land(land: "Numidia", people: "the Numidians", ruler: "Hiarbas", temperament: .proud, look: "libyan", climate: .warm),
        Land(land: "Mauretania", people: "the Mauri", ruler: "Bocchus", temperament: .peaceable, look: "libyan", climate: .dry),
        // More of the age.
        Land(land: "Wilusa", people: "Wilusa", ruler: "Alaksandu", temperament: .proud, look: "hatti", climate: .warm),
        Land(land: "Arzawa", people: "Arzawa", ruler: "Tarhuntaradu", temperament: .proud, look: "hatti", climate: .warm),
        Land(land: "Kaska", people: "the Kaska", ruler: "Pihhuniya", temperament: .warlike, look: "north", climate: .high),
        Land(land: "Mitanni", people: "Mitanni", ruler: "Tushratta", temperament: .proud, look: "mesopotamia", climate: .warm),
        Land(land: "Hurri", people: "the Hurrians", ruler: "Shuttarna", temperament: .proud, look: "mesopotamia", climate: .high),
        Land(land: "Karduniash", people: "the Kassites", ruler: "Kurigalzu", temperament: .proud, look: "mesopotamia", climate: .dry),
        Land(land: "Amurru", people: "the Amorites", ruler: "Aziru", temperament: .warlike, look: "mesopotamia", climate: .dry),
        Land(land: "Canaan", people: "the Canaanites", ruler: "Abdi-Heba", temperament: .mercantile, look: "mesopotamia", climate: .warm),
        Land(land: "Byblos", people: "Byblos", ruler: "Rib-Hadda", temperament: .mercantile, look: "mesopotamia", climate: .sea),
        Land(land: "Sidon", people: "Sidon", ruler: "Zimrida", temperament: .mercantile, look: "mesopotamia", climate: .sea),
        Land(land: "Tyre", people: "Tyre", ruler: "Abimilki", temperament: .mercantile, look: "mesopotamia", climate: .sea),
        Land(land: "Karkemish", people: "Karkemish", ruler: "Kuzi-Teshub", temperament: .proud, look: "hatti", climate: .warm),
        Land(land: "Yamhad", people: "Yamhad", ruler: "Yarim-Lim", temperament: .proud, look: "mesopotamia", climate: .warm),
        Land(land: "Mari", people: "Mari", ruler: "Zimri-Lim", temperament: .mercantile, look: "mesopotamia", climate: .dry),
        Land(land: "Qatna", people: "Qatna", ruler: "Idanda", temperament: .peaceable, look: "mesopotamia", climate: .dry),
        Land(land: "Philistia", people: "the Peleset", ruler: "Achish", temperament: .warlike, look: "greece", climate: .sea),
        Land(land: "Mycenae", people: "Mycenae", ruler: "Atreus", temperament: .proud, look: "greece", climate: .high),
        Land(land: "Pylos", people: "Pylos", ruler: "Nestor", temperament: .peaceable, look: "greece", climate: .sea),
        Land(land: "Tiryns", people: "Tiryns", ruler: "Proetus", temperament: .warlike, look: "greece", climate: .high),
        Land(land: "Boeotia", people: "Thebes", ruler: "Cadmus", temperament: .proud, look: "greece", climate: .warm),
        Land(land: "Achaea", people: "the Achaeans", ruler: "Tisamenus", temperament: .warlike, look: "greece", climate: .warm),
        Land(land: "Rhodes", people: "the Rhodians", ruler: "Tlepolemus", temperament: .mercantile, look: "greece", climate: .sea),
        Land(land: "Ithaca", people: "Ithaca", ruler: "Laertes", temperament: .peaceable, look: "greece", climate: .sea),
        Land(land: "Phrygia", people: "the Phrygians", ruler: "Gordias", temperament: .proud, look: "hatti", climate: .high),
        Land(land: "Isuwa", people: "Isuwa", ruler: "Ehli-Sharruma", temperament: .peaceable, look: "hatti", climate: .high),
        Land(land: "Kizzuwatna", people: "Kizzuwatna", ruler: "Sunassura", temperament: .mercantile, look: "hatti", climate: .warm),
        Land(land: "Kush", people: "Kush", ruler: "Kashta", temperament: .proud, look: "libyan", climate: .dry),
        Land(land: "Punt", people: "Punt", ruler: "Parahu", temperament: .mercantile, look: "libyan", climate: .dry),
        Land(land: "Wawat", people: "the Medjay", ruler: "Irem", temperament: .warlike, look: "libyan", climate: .dry),
        Land(land: "Dilmun", people: "Dilmun", ruler: "Uperi", temperament: .mercantile, look: "mesopotamia", climate: .sea),
        Land(land: "Magan", people: "Magan", ruler: "Manium", temperament: .mercantile, look: "mesopotamia", climate: .dry),
        Land(land: "Gutium", people: "the Guti", ruler: "Tirigan", temperament: .warlike, look: "chief", climate: .high),
        Land(land: "Lullubum", people: "the Lullubi", ruler: "Anubanini", temperament: .warlike, look: "chief", climate: .high),
        Land(land: "Etruria", people: "the Tyrrhenians", ruler: "Tarchon", temperament: .mercantile, look: "chief", climate: .warm),
        Land(land: "Latium", people: "the Latins", ruler: "Latinus", temperament: .proud, look: "chief", climate: .warm),
        Land(land: "Liguria", people: "the Ligures", ruler: "Cycnus", temperament: .warlike, look: "chief", climate: .high),
        Land(land: "Illyria", people: "the Illyrians", ruler: "Bardylis", temperament: .warlike, look: "north", climate: .high),
        Land(land: "Pannonia", people: "the Pannonians", ruler: "Bato", temperament: .proud, look: "north", climate: .cold),
        Land(land: "Noricum", people: "the Norici", ruler: "Voccio", temperament: .mercantile, look: "north", climate: .cold),
        Land(land: "Cimmeria", people: "the Cimmerians", ruler: "Teushpa", temperament: .warlike, look: "north", climate: .cold),
        Land(land: "Colchis", people: "Colchis", ruler: "Kuji", temperament: .mercantile, look: "hatti", climate: .warm),
        Land(land: "Lusitania", people: "the Lusitani", ruler: "Viriathus", temperament: .warlike, look: "chief", climate: .high),
        Land(land: "Armorica", people: "the Armoricans", ruler: "Conan", temperament: .peaceable, look: "north", climate: .cold),
        Land(land: "Balearia", people: "the Talaiotic folk", ruler: "Tirant", temperament: .peaceable, look: "chief", climate: .sea),
        Land(land: "Malta", people: "the Temple-builders", ruler: "Ggantija", temperament: .peaceable, look: "chief", climate: .sea),
    ]

    /// Lands of the wandering tribes, where migrations start.
    static let homelands: [(name: String, climate: Climate)] = [
        ("Caledonia", .cold), ("Suebi", .cold), ("Venedi", .cold), ("Scythe", .cold), ("Sarmatia", .cold),
        ("Daha", .dry), ("Arabia", .dry), ("Sahara", .dry), ("Massagetae", .cold), ("Garamantes", .dry),
        ("Tjehenu", .dry), ("Aestii", .cold), ("Budini", .cold), ("Gaetulia", .dry), ("Bastarnae", .cold),
        ("Hyperborea", .cold), ("Thyssagetae", .high), ("Blemmyes", .dry), ("Aethiopia", .dry), ("Riphaei", .high),
    ]

    static let seas: [String] = [
        "Mare Internum", "Mare Aegaeum", "Mare Ionium", "Mare Tyrrhenum", "Mare Balearicum", "Mare Libycum",
        "Mare Creticum", "Mare Myrtoum", "Mare Icarium", "Mare Carpathium", "Mare Cilicium", "Mare Pamphylium",
        "Mare Sardoum", "Mare Ligusticum", "Mare Superum", "Mare Erythraeum", "Pontus Euxinus", "Propontis",
        "Palus Maeotis", "Mare Hyrcanum", "Sinus Arabicus", "Sinus Persicus", "Oceanus Atlanticus",
        "Oceanus Germanicus", "Mare Suebicum", "Mare Cronium", "Mare Cantabricum", "Mare Thracium",
    ]
}
