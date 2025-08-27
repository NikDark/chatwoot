class AddMaxChannel < ActiveRecord::Migration[7.1]
  def change
    create_table :channel_max do |t|
      t.integer :account_id, null: false
      t.string :bot_token, null: false
      t.string :bot_name
      t.timestamps
    end

    add_index :channel_max, :bot_token, unique: true
    add_foreign_key :channel_max, :accounts, on_delete: :cascade
  end
end

