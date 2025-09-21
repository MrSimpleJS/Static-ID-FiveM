-- Separate static ID table (optional mode)
-- Enable via Config.DB.UseSeparateStaticTable = true

CREATE TABLE IF NOT EXISTS `static_ids` (
  `static_id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `identifier` VARCHAR(64) NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`static_id`),
  UNIQUE KEY `uniq_identifier` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
